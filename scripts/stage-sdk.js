const fs = require('fs');
const path = require('path');

const PLUGIN_ID = 'cordova-plugin-imatch';
const VARIABLE = 'IMATCH_SDK_DIR';
const DEFAULT_SDK_DIR = 'imatch-sdk';
const REQUEST_HINT =
    'Request the iMatch SDK for Cordova from BPI Services (support@bpiservices.eu) and unzip it into ' +
    '<project>/' + DEFAULT_SDK_DIR + ' (or pass --variable ' + VARIABLE + '=<folder>). ' +
    'See sdk/README.md in the plugin.';

const PLATFORM_FILES = {
    android: ['android/imatchsdk.aar'],
    ios: ['ios/iMatchSDK.xcframework']
};

function compareVersions(a, b) {
    const pa = String(a).split('.').map(Number);
    const pb = String(b).split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const d = (pa[i] || 0) - (pb[i] || 0);
        if (d !== 0) return d;
    }
    return 0;
}

function exists(p) {
    try {
        fs.statSync(p);
        return true;
    } catch (e) {
        return false;
    }
}

function variableFromArgv() {
    const argv = process.argv;
    for (let i = 0; i < argv.length; i++) {
        let assignment = null;
        if (argv[i] === '--variable' && i + 1 < argv.length) {
            assignment = argv[i + 1];
        } else if (argv[i].startsWith('--variable=')) {
            assignment = argv[i].substring('--variable='.length);
        }
        if (assignment && assignment.startsWith(VARIABLE + '=')) {
            return assignment.substring(VARIABLE.length + 1);
        }
    }
    return null;
}

function variableFromProject(context, projectRoot) {
    try {
        const pkg = JSON.parse(fs.readFileSync(path.join(projectRoot, 'package.json'), 'utf8'));
        const saved = pkg.cordova && pkg.cordova.plugins && pkg.cordova.plugins[PLUGIN_ID];
        if (saved && saved[VARIABLE]) return saved[VARIABLE];
    } catch (e) {
    }
    try {
        const { ConfigParser } = context.requireCordovaModule('cordova-common');
        const plugin = new ConfigParser(path.join(projectRoot, 'config.xml')).getPlugin(PLUGIN_ID);
        if (plugin && plugin.variables && plugin.variables[VARIABLE]) return plugin.variables[VARIABLE];
    } catch (e) {
    }
    return null;
}

function candidateDirs(context, pluginDir) {
    const projectRoot = context.opts.projectRoot;
    const dirs = [];
    const fromVariable = variableFromArgv() || variableFromProject(context, projectRoot);
    if (fromVariable) dirs.push(path.resolve(projectRoot, fromVariable));
    if (process.env[VARIABLE]) dirs.push(path.resolve(projectRoot, process.env[VARIABLE]));
    dirs.push(path.resolve(projectRoot, DEFAULT_SDK_DIR));
    dirs.push(path.join(pluginDir, 'sdk'));
    return dirs;
}

function copyInto(pluginSdkDir, sourceDir, relative) {
    const from = path.join(sourceDir, relative);
    const to = path.join(pluginSdkDir, relative);
    if (path.resolve(from) === path.resolve(to)) return;
    fs.rmSync(to, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.cpSync(from, to, { recursive: true });
}

module.exports = function (context) {
    const plugin = context.opts.plugin;
    const pluginDir = plugin.dir;
    const platform = plugin.platform;
    const pluginVersion = plugin.pluginInfo.version;
    const files = PLATFORM_FILES[platform];
    if (!files) return;

    const pluginSdkDir = path.join(pluginDir, 'sdk');
    const dirs = candidateDirs(context, pluginDir);
    const sourceDir = dirs.find(dir => exists(path.join(dir, files[0])));
    if (!sourceDir) {
        throw new Error(
            PLUGIN_ID + ': iMatch SDK binaries for ' + platform + ' not found (' + files[0] + ').\n' +
            'Looked in: ' + dirs.join(', ') + '\n' + REQUEST_HINT
        );
    }

    files.forEach(relative => copyInto(pluginSdkDir, sourceDir, relative));
    if (exists(path.join(sourceDir, 'sdk-version.json'))) {
        copyInto(pluginSdkDir, sourceDir, 'sdk-version.json');
    }

    const versionFile = path.join(pluginSdkDir, 'sdk-version.json');
    if (!exists(versionFile)) {
        console.warn(PLUGIN_ID + ': sdk-version.json not found in ' + sourceDir + ', skipping SDK version check');
        return;
    }

    let info;
    try {
        info = JSON.parse(fs.readFileSync(versionFile, 'utf8'));
    } catch (e) {
        console.warn(PLUGIN_ID + ': could not read sdk-version.json: ' + e.message);
        return;
    }

    if (info.minPlugin && compareVersions(pluginVersion, info.minPlugin) < 0) {
        throw new Error(
            PLUGIN_ID + ': the SDK drop requires plugin version ' + info.minPlugin +
            ' or newer, but this plugin is ' + pluginVersion + '. Update the plugin.'
        );
    }
    if (info.maxPlugin && compareVersions(pluginVersion, info.maxPlugin) > 0) {
        console.warn(
            PLUGIN_ID + ': this SDK drop was released for plugin versions up to ' + info.maxPlugin +
            '. Request a newer SDK drop from BPI if you run into problems.'
        );
    }

    console.log(PLUGIN_ID + ': using iMatch SDK ' + (info[platform] || 'unknown') + ' for ' + platform + ' from ' + sourceDir);
};
