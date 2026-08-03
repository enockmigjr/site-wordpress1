<?php
$source = __DIR__ . '/wp-content/plugins';
$dest = __DIR__ . '/wp-content/themes/PhotoVault/plugins';
$plugins = ['identity-security-kit', 'newsletter-campaign-kit', 'photovault-core', 'trouble-ticket-connector'];

function delete_directory($dir) {
    if (!file_exists($dir)) {
        return true;
    }
    if (is_link($dir)) {
        return false;
    }
    if (!is_dir($dir)) {
        chmod($dir, 0666);
        return unlink($dir);
    }
    foreach (scandir($dir) as $item) {
        if ($item == '.' || $item == '..') {
            continue;
        }
        if (!delete_directory($dir . DIRECTORY_SEPARATOR . $item)) {
            return false;
        }
    }
    return rmdir($dir);
}

function assert_safe_plugin_path($path, $root, $plugin) {
    $rootPath = realpath($root);
    $parentPath = realpath(dirname($path));
    if ($rootPath === false || $parentPath === false || $parentPath !== $rootPath || basename($path) !== $plugin || is_link($path)) {
        throw new RuntimeException('Unsafe plugin path: ' . $path);
    }
}

function clear_plugin_mirror($directory) {
    if (!is_dir($directory)) {
        return mkdir($directory, 0755, true);
    }
    foreach (scandir($directory) as $item) {
        if ($item === '.' || $item === '..' || $item === '.git' || $item === 'vendor' || $item === 'node_modules') {
            continue;
        }
        $path = $directory . DIRECTORY_SEPARATOR . $item;
        if (is_dir($path)) {
            if (!clear_plugin_mirror($path)) {
                return false;
            }
        } elseif (!delete_directory($path)) {
            return false;
        }
    }
    return true;
}

function copy_directory($src, $dst) {
    if (!is_dir($dst)) {
        mkdir($dst, 0755, true);
    }
    $dir = opendir($src);
    while (false !== ($file = readdir($dir))) {
        if ($file === '.' || $file === '..' || $file === '.git' || $file === 'vendor' || $file === 'node_modules') {
            continue;
        }
        $srcPath = $src . '/' . $file;
        $dstPath = $dst . '/' . $file;
        if (is_dir($srcPath)) {
            copy_directory($srcPath, $dstPath);
        } else {
            copy($srcPath, $dstPath);
        }
    }
    closedir($dir);
}

foreach ($plugins as $plugin) {
    echo "Syncing $plugin...\n";
    $srcPath = $source . '/' . $plugin;
    $dstPath = $dest . '/' . $plugin;
    assert_safe_plugin_path($srcPath, $source, $plugin);
    assert_safe_plugin_path($dstPath, $dest, $plugin);
    if (!is_dir($srcPath)) {
        throw new RuntimeException('Missing plugin source: ' . $srcPath);
    }
    if (!clear_plugin_mirror($dstPath)) {
        throw new RuntimeException('Unable to clear plugin mirror safely: ' . $dstPath);
    }
    copy_directory($srcPath, $dstPath);
}
echo "Done.\n";
