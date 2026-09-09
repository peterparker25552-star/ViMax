package com.vimax.mobile

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

/**
 * ViMax Android app.
 *
 * The app is a focused WebView shell around the ViMax web workspace. By
 * default it loads the workspace bundle shipped inside the APK
 * (assets/www), which talks to the ViMax engine bridge over HTTP:
 *
 *  - on-device engine:  http://127.0.0.1:4173   (Termux on the same phone)
 *  - LAN engine:        http://<computer-ip>:4173
 *
 * The engine address is configurable in the overflow menu and stored in
 * shared preferences. Rendered videos are handed to the system download
 * manager so they land in the gallery/downloads folder.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        const val PREFS = "vimax_prefs"
        const val KEY_ENGINE_URL = "engine_url"
        const val KEY_USE_BUNDLED = "use_bundled_app"
        const val DEFAULT_ENGINE = "http://127.0.0.1:4173"
    }

    private lateinit var webView: WebView
    private lateinit var refreshLayout: SwipeRefreshLayout
    private lateinit var offlineBar: TextView

    private var fileUploadCallback: ValueCallback<Array<Uri>>? = null

    private val fileChooserLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val callback = fileUploadCallback ?: return@registerForActivityResult
            val uris = WebAppFileSupport.selectedFiles(result)
            callback.onReceiveValue(uris)
            fileUploadCallback = null
        }

    private val appUrl: String
        get() = "file:///android_asset/www/index.html"

    private fun engineUrl(): String =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ENGINE_URL, DEFAULT_ENGINE)?.trim().takeUnless { it.isNullOrEmpty() }
            ?: DEFAULT_ENGINE

    private fun useBundledApp(): Boolean =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_USE_BUNDLED, true)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.web_view)
        refreshLayout = findViewById(R.id.refresh_layout)
        offlineBar = findViewById(R.id.offline_bar)

        setupWebView()
        loadApp()

        findViewById<TextView>(R.id.offline_retry).setOnClickListener { loadApp() }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            loadWithOverviewMode = true
            useWideViewPort = true
            mediaPlaybackRequiresUserGesture = false
            javaScriptCanOpenWindowsAutomatically = false
        }
        webView.setBackgroundColor(getColor(R.color.canvas))

        webView.webViewClient = object : WebViewClient() {
            // Inject the configured engine address into the bundled UI before
            // any app script runs, so the workspace talks to the right engine
            // even when loaded from a file:// asset.
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): android.webkit.WebResourceResponse? {
                val url = request.url
                if (url.scheme == "file" && url.path?.endsWith("/index.html") == true) {
                    return runCatching {
                        val html = assets.open("www/index.html").bufferedReader().use { it.readText() }
                        val engine = engineUrl().replace("\\", "\\\\").replace("\"", "\\\"")
                        val inject = "<script>window.VIMAX_ENGINE_URL=\"$engine\";</script></head>"
                        val patched = html.replaceFirst("</head>", inject, ignoreCase = true)
                        android.webkit.WebResourceResponse(
                            "text/html",
                            "utf-8",
                            java.io.ByteArrayInputStream(patched.toByteArray()),
                        )
                    }.getOrNull()
                }
                return null
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                // Keep the bundled app and the configured engine inside the shell;
                // everything else (auth pages, docs, provider dashboards) opens
                // in the user's browser.
                val internal = url.scheme == "file" || url.toString().startsWith(engineUrl())
                if (!internal) {
                    runCatching { startActivity(Intent(Intent.ACTION_VIEW, url)) }
                    return true
                }
                return false
            }

            override fun onPageFinished(view: WebView, url: String) {
                refreshLayout.isRefreshing = false
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: android.webkit.WebResourceError) {
                if (request.isForMainFrame) {
                    offlineBar.isVisible = true
                    refreshLayout.isRefreshing = false
                }
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                view: WebView,
                callback: ValueCallback<Array<Uri>>,
                params: FileChooserParams,
            ): Boolean {
                if (fileUploadCallback != null) fileUploadCallback?.onReceiveValue(null)
                fileUploadCallback = callback
                val intent = params.createIntent().apply { addCategory(Intent.CATEGORY_OPENABLE) }
                return try {
                    fileChooserLauncher.launch(intent)
                    true
                } catch (error: android.content.ActivityNotFoundException) {
                    fileUploadCallback = null
                    false
                }
            }
        }

        // Rendered videos / artifacts -> system download manager.
        webView.setDownloadListener(DownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            WebAppFileSupport.download(this, url, userAgent, contentDisposition, mimeType)
        })

        webView.setOnScrollChangeListener { _, _, scrollY, _, _ ->
            refreshLayout.isEnabled = scrollY == 0
        }

        refreshLayout.setColorSchemeColors(getColor(R.color.blue))
        refreshLayout.setOnRefreshListener { loadApp() }
    }

    private fun loadApp() {
        offlineBar.isVisible = false
        CookieManager.getInstance().setAcceptCookie(true)
        if (useBundledApp()) {
            webView.loadUrl(appUrl)
        } else {
            webView.loadUrl(engineUrl())
        }
    }

    private fun showEngineSettings() {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        val padding = (16 * resources.displayMetrics.density).toInt()
        layout.setPadding(padding, padding, padding, 0)

        val engineInput = EditText(this).apply {
            hint = "http://192.168.1.20:4173"
            setText(engineUrl())
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_URI
            singleLine = true
        }
        layout.addView(engineInput)

        val options = arrayOf(
            getString(R.string.pref_bundled_ui),
            getString(R.string.pref_engine_ui),
        )
        val checked = intArrayOf(useBundledApp().compareTo(false))
        AlertDialog.Builder(this)
            .setTitle(R.string.engine_settings_title)
            .setView(layout)
            .setMultiChoiceItems(options, booleanArrayOf(useBundledApp(), !useBundledApp())) { _, which, isChecked ->
                checked[which] = if (isChecked) 1 else 0
            }
            .setPositiveButton(R.string.save) { _, _ ->
                val url = engineInput.text.toString().trim().trimEnd('/')
                val useBundled = checked[0] == 1 || checked[1] == 0
                getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_ENGINE_URL, if (url.isEmpty()) DEFAULT_ENGINE else url)
                    .putBoolean(KEY_USE_BUNDLED, useBundled)
                    .apply()
                Toast.makeText(this, R.string.saved, Toast.LENGTH_SHORT).show()
                loadApp()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        menu.findItem(R.id.action_keep_awake).isChecked = keepAwake
        return true
    }

    private var keepAwake: Boolean = false

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        R.id.action_reload -> {
            loadApp(); true
        }
        R.id.action_engine -> {
            showEngineSettings(); true
        }
        R.id.action_keep_awake -> {
            keepAwake = !keepAwake
            item.isChecked = keepAwake
            webView.keepScreenOn = keepAwake
            true
        }
        else -> super.onOptionsItemSelected(item)
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack() else super.onBackPressed()
    }

    override fun onPause() {
        webView.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }
}
