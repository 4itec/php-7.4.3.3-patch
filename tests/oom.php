<?php
// Isolated regression check for the official patch's new OOM exit behavior.
$marker = $argv[1];
register_shutdown_function(function () use ($marker) {
    file_put_contents($marker, 'shutdown callback executed');
});
$allocation = str_repeat('x', 64 * 1024 * 1024);
fwrite(STDERR, 'Expected memory exhaustion did not occur');
exit(2);
