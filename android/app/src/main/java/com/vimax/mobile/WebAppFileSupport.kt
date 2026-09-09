package com.vimax.mobile

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.URLUtil
import android.widget.Toast
import androidx.activity.result.ActivityResult
import java.io.File

/** File plumbing for the WebView shell: uploads in, rendered videos out. */
object WebAppFileSupport {

    /** Convert a file-chooser result into the Uri array the WebView expects. */
    fun selectedFiles(result: ActivityResult): Array<Uri>? {
        if (result.resultCode != android.app.Activity.RESULT_OK) return null
        val data = result.data ?: return null
        val clip = data.clipData
        return when {
            clip != null -> Array(clip.itemCount) { index -> clip.getItemAt(index).uri }
            data.dataString != null -> arrayOf(Uri.parse(data.dataString))
            else -> null
        }
    }

    /**
     * Queue a download (typically a rendered ViMax video artifact) through
     * the system download manager so it lands in the public Downloads folder
     * and shows up in gallery apps.
     */
    fun download(
        context: Context,
        url: String,
        userAgent: String?,
        contentDisposition: String?,
        mimeType: String?,
    ) {
        try {
            val fileName = URLUtil.guessFileName(url, contentDisposition, mimeType)
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setTitle(fileName)
                setDescription("ViMax render")
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "ViMax/$fileName")
                setMimeType(mimeType)
                userAgent?.let { addRequestHeader("User-Agent", it) }
            }
            val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            manager.enqueue(request)
            Toast.makeText(context, context.getString(R.string.download_started, fileName), Toast.LENGTH_SHORT).show()
        } catch (error: Exception) {
            Toast.makeText(context, context.getString(R.string.download_failed, error.message ?: "error"), Toast.LENGTH_LONG).show()
        }
    }
}
