import {readFile, rename, writeFile} from 'node:fs/promises';
import path from 'node:path';

// The 'yaml' npm package is only needed for reading/writing the provider
// configuration. Importing it lazily keeps the ViMax server usable (chat,
// artifacts, renders) even on hosts where the web dependencies were not
// installed — e.g. a fresh clone on Android/Termux — and only the Settings
// screen reports a clear remediation message.
let yamlModule = null;

async function loadYaml() {
  if (yamlModule) return yamlModule;
  try {
    yamlModule = await import('yaml');
    return yamlModule;
  } catch {
    throw new Error(
      "The 'yaml' package is missing. From the repository's web/ directory run: npm install --omit=dev"
    );
  }
}

const SECTION_FIELDS = {
  llm: ['model_provider', 'model', 'base_url'],
  image: ['provider', 'model', 'base_url'],
  video: ['provider', 'model', 'base_url'],
  embedding: ['model_provider', 'model', 'base_url'],
  reranker: ['model', 'base_url'],
};

export async function readAgentConfig(repoRoot) {
  const {payload} = await loadConfig(repoRoot);
  return publicConfig(payload);
}

export async function saveAgentConfig(repoRoot, input) {
  if (!input || typeof input !== 'object' || !input.sections || typeof input.sections !== 'object') {
    throw new Error('Configuration sections are required');
  }
  const {configPath, payload} = await loadConfig(repoRoot);
  for (const [section, fields] of Object.entries(SECTION_FIELDS)) {
    const update = input.sections[section];
    if (!update || typeof update !== 'object') continue;
    const current = payload[section] && typeof payload[section] === 'object' ? payload[section] : {};
    for (const field of fields) {
      if (!(field in update)) continue;
      current[field] = validatedValue(update[field], `${section}.${field}`, 2_048);
    }
    if (typeof update.api_key === 'string' && update.api_key.trim()) {
      current.api_key = validatedValue(update.api_key, `${section}.api_key`, 8_192);
    }
    payload[section] = current;
  }
  const temporaryPath = `${configPath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, stringify(payload, {lineWidth: 0}), {mode: 0o600});
  await rename(temporaryPath, configPath);
  return publicConfig(payload);
}

async function loadConfig(repoRoot) {
  const {parse} = await loadYaml();
  const configPath = path.join(repoRoot, 'configs', 'agent.local.yaml');
  let text = '';
  try {
    text = await readFile(configPath, 'utf8');
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  const payload = text ? parse(text) : {};
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new Error('configs/agent.local.yaml must be a YAML mapping');
  }
  return {configPath, payload};
}

function publicConfig(payload) {
  const sections = {};
  for (const [section, fields] of Object.entries(SECTION_FIELDS)) {
    const source = payload[section] && typeof payload[section] === 'object' ? payload[section] : {};
    const result = {};
    for (const field of fields) result[field] = typeof source[field] === 'string' ? source[field] : '';
    result.api_key = '';
    result.has_api_key = Boolean(typeof source.api_key === 'string' && source.api_key.trim());
    sections[section] = result;
  }
  return {sections};
}

function validatedValue(value, label, maxLength) {
  if (typeof value !== 'string') throw new Error(`${label} must be a string`);
  const normalized = value.trim();
  if (normalized.length > maxLength) throw new Error(`${label} is too long`);
  if (label.endsWith('.base_url') && normalized && !/^https?:\/\//i.test(normalized)) {
    throw new Error(`${label} must use http:// or https://`);
  }
  return normalized;
}
