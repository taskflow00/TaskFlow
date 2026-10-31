<?php

require_once 'backend/supabase.php';

$result = supabase_request('/rest/v1/profiles?select=id&limit=1');

echo '<pre>';
print_r($result);
echo '</pre>';