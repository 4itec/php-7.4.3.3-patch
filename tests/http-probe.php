<?php
session_start();
$previous = isset($_SESSION['probe']) ? $_SESSION['probe'] : null;
$_SESSION['probe'] = 'persisted';
header('Content-Type: application/json');
echo json_encode([
    'version' => PHP_VERSION,
    'method' => $_SERVER['REQUEST_METHOD'],
    'previous' => $previous,
    'field' => isset($_POST['field']) ? $_POST['field'] : null,
    'uploaded' => isset($_FILES['upload']) && $_FILES['upload']['error'] === UPLOAD_ERR_OK,
    'progress_present' => array_key_exists('upload_progress_probe', $_SESSION)
]);

