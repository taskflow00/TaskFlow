<?php

// Load environment variables
$env = parse_ini_file(__DIR__ . '/../.env');

if (!$env) {
    die("Environment configuration not found.");
}

// Supabase configuration
define('SUPABASE_URL', $env['SUPABASE_URL']);
define('SUPABASE_ANON_KEY', $env['SUPABASE_ANON_KEY']);

// Reusable Supabase request function
function supabase_request($endpoint, $method = 'GET', $body = null, $accessToken = null)
{
    $token = $accessToken ?? SUPABASE_ANON_KEY;

    $headers = [
        'apikey: ' . SUPABASE_ANON_KEY,
        'Authorization: Bearer ' . $token,
        'Content-Type: application/json'
    ];

    $options = [
        'http' => [
            'method' => $method,
            'header' => implode("\r\n", $headers),
            'ignore_errors' => true
        ]
    ];

    if ($body !== null) {
        $options['http']['content'] = json_encode($body);
    }

    $context = stream_context_create($options);

    $response = file_get_contents(
        SUPABASE_URL . $endpoint,
        false,
        $context
    );

    $status = $http_response_header[0] ?? 'HTTP/1.1 500 Unknown Error';

    return [
        'status' => (int) explode(' ', $status)[1],
        'data' => json_decode($response ?: 'null', true)
    ];
}