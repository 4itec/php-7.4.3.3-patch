<?php
// Executed only by the newly compiled CLI in an isolated test directory.
function ensure($ok, $message) {
    if (!$ok) {
        fwrite(STDERR, $message . PHP_EOL);
        exit(1);
    }
}
$dir = $argv[1];
ensure(PHP_VERSION === '7.4.33-pl1', 'Unexpected version');
ensure(PHP_INT_SIZE === 8 && PHP_ZTS, 'Expected x64 Thread Safe');
$required = ['curl','fileinfo','gd','intl','mbstring','mysqli','openssl','PDO','pdo_mysql','pdo_sqlite','session','zip','Zend OPcache'];
foreach ($required as $name) {
    ensure(extension_loaded($name), 'Missing extension: ' . $name);
}
ensure(json_decode(json_encode(['text' => 'España 漢字']), true)['text'] === 'España 漢字', 'JSON Unicode');
ensure(mb_strlen('España', 'UTF-8') === 6, 'mbstring');
ensure(openssl_digest('abc', 'sha256') === hash('sha256', 'abc'), 'OpenSSL digest');
ensure(Normalizer::normalize("e\xCC\x81") === "\xC3\xA9", 'ICU normalization');
$image = imagecreatetruecolor(8, 8);
ensure($image !== false && imagepng($image, $dir . '/image.png'), 'GD PNG');
imagedestroy($image);
$zip = new ZipArchive();
ensure($zip->open($dir . '/roundtrip.zip', ZipArchive::CREATE) === true, 'ZIP create');
ensure($zip->addFromString('test.txt', 'roundtrip'), 'ZIP add');
ensure($zip->close(), 'ZIP close');
ensure($zip->open($dir . '/roundtrip.zip') === true && $zip->getFromName('test.txt') === 'roundtrip', 'ZIP read');
$zip->close();
$db = new PDO('sqlite::memory:');
$db->exec('CREATE TABLE probe (value TEXT)');
$stmt = $db->prepare('INSERT INTO probe VALUES (?)');
$stmt->execute(['parameterized']);
ensure($db->query('SELECT value FROM probe')->fetchColumn() === 'parameterized', 'PDO SQLite');
ini_set('session.save_path', $dir);
session_id('functionalprobe');
ensure(session_start(), 'Session start');
$_SESSION['probe'] = 'roundtrip';
session_write_close();
ensure(session_start() && $_SESSION['probe'] === 'roundtrip', 'Session persistence');
session_destroy();
echo json_encode([
    'status' => 'passed',
    'version' => PHP_VERSION,
    'sapi' => PHP_SAPI,
    'int_size' => PHP_INT_SIZE,
    'zts' => PHP_ZTS,
    'openssl' => OPENSSL_VERSION_TEXT,
    'icu' => INTL_ICU_VERSION,
    'curl' => curl_version(),
    'gd' => gd_info(),
    'extensions' => get_loaded_extensions()
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE), PHP_EOL;

