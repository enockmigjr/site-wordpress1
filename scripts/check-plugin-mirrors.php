<?php
/**
 * Fail when an installed PhotoVault plugin differs from its theme mirror.
 *
 * This checker is intentionally read-only so it is safe to run locally and in CI.
 */

declare(strict_types=1);

$root = dirname(__DIR__);
$plugins = array(
	'identity-security-kit',
	'newsletter-campaign-kit',
	'photovault-core',
	'trouble-ticket-connector',
);

/** @return array<string, string> */
function photovault_mirror_manifest(string $directory): array {
	$manifest = array();
	$iterator = new RecursiveIteratorIterator(
		new RecursiveDirectoryIterator($directory, FilesystemIterator::SKIP_DOTS),
		RecursiveIteratorIterator::LEAVES_ONLY
	);
	foreach ($iterator as $file) {
		if (! $file instanceof SplFileInfo || ! $file->isFile() || $file->isLink()) {
			continue;
		}
		$relative = str_replace('\\', '/', substr($file->getPathname(), strlen($directory) + 1));
		if (preg_match('#(^|/)(?:\.git|vendor|node_modules)(?:/|$)#', $relative)) {
			continue;
		}
		$hash = hash_file('sha256', $file->getPathname());
		if (! is_string($hash)) {
			throw new RuntimeException(sprintf('Unable to hash %s.', $file->getPathname()));
		}
		$manifest[$relative] = $hash;
	}
	ksort($manifest);
	return $manifest;
}

$failures = array();
foreach ($plugins as $plugin) {
	$installed = $root . '/wp-content/plugins/' . $plugin;
	$mirror = $root . '/wp-content/themes/PhotoVault/plugins/' . $plugin;
	if (! is_dir($installed) || ! is_dir($mirror)) {
		$failures[] = sprintf('%s: installed plugin or theme mirror is missing.', $plugin);
		continue;
	}
	try {
		$installedManifest = photovault_mirror_manifest($installed);
		$mirrorManifest = photovault_mirror_manifest($mirror);
	} catch (Throwable $exception) {
		$failures[] = sprintf('%s: %s', $plugin, $exception->getMessage());
		continue;
	}
	$paths = array_values(array_unique(array_merge(array_keys($installedManifest), array_keys($mirrorManifest))));
	sort($paths);
	foreach ($paths as $path) {
		if (($installedManifest[$path] ?? null) !== ($mirrorManifest[$path] ?? null)) {
			$failures[] = sprintf('%s: %s differs.', $plugin, $path);
		}
	}
}

if ($failures) {
	fwrite(STDERR, "Plugin mirror check failed:\n- " . implode("\n- ", $failures) . "\n");
	exit(1);
}

fwrite(STDOUT, "Plugin mirrors are identical.\n");
