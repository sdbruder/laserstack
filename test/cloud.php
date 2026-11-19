<?php
/**
 * One round trip per cloud emulator of laserstack, from inside a project.
 *
 *   php test/cloud.php s3      the S3 API of RustFS: a bucket, an object, a read
 *   php test/cloud.php aws     the AWS API of Floci: the same over S3, and a queue
 *   php test/cloud.php gcs     the Cloud Storage JSON API of fake-gcs-server
 *   php test/cloud.php azure   the blob service of Azurite
 *
 * Every service answers the protocol of its provider, so this file signs its
 * requests the way the SDK of a project does: SigV4 for the two AWS shapes and
 * SharedKey for the Azure one. Only the standard library takes part, so it runs
 * on every PHP version of the stack, and no credential of a real cloud account
 * appears anywhere.
 *
 * The default endpoints are the names of the profiles on the network of the
 * stack. S3_ENDPOINT, AWS_ENDPOINT, GCS_ENDPOINT and AZURE_ENDPOINT override
 * them, so the same file works from the host against a published port:
 *
 *   S3_ENDPOINT=http://127.0.0.1:9000 php test/cloud.php s3
 */

$service = $argv[1] ?? '';

function fail(string $message): void
{
    fwrite(STDERR, "not ok: $message\n");
    exit(1);
}

/**
 * One request. Returns [status, body].
 */
function request(string $method, string $url, array $headers = [], ?string $body = null): array
{
    $header = '';
    foreach ($headers as $name => $value) {
        $header .= "$name: $value\r\n";
    }
    $options = [
        'method' => $method,
        'header' => $header,
        'ignore_errors' => true,
        'timeout' => 10,
    ];
    // no "content" for a request without a body: PHP adds a Content-Length of
    // its own, and Azure signs the length of the body the caller passed
    if ($body !== null) {
        $options['content'] = $body;
    }
    $context = stream_context_create(['http' => $options]);
    $answer = @file_get_contents($url, false, $context);
    if ($answer === false) {
        fail("$method $url: no answer");
    }
    $status = 0;
    foreach ($http_response_header ?? [] as $line) {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $line, $match)) {
            $status = (int) $match[1];
        }
    }
    return [$status, $answer];
}

/**
 * The headers of one SigV4 request, which is what the AWS SDKs build.
 */
function sigv4(string $method, string $url, string $service, string $key, string $secret, ?string $body = null): array
{
    $region = 'us-east-1';
    $parts = parse_url($url);
    $host = $parts['host'] . ':' . $parts['port'];
    $payload = hash('sha256', $body ?? '');
    $now = gmdate('Ymd\THis\Z');
    $date = gmdate('Ymd');
    $headers = [
        'host' => $host,
        'x-amz-content-sha256' => $payload,
        'x-amz-date' => $now,
    ];
    ksort($headers);
    $canonical = '';
    foreach ($headers as $name => $value) {
        $canonical .= "$name:$value\n";
    }
    $names = implode(';', array_keys($headers));
    $canonicalRequest = implode("\n", [
        $method,
        $parts['path'] ?: '/',
        $parts['query'] ?? '',
        $canonical,
        $names,
        $payload,
    ]);
    $scope = "$date/$region/$service/aws4_request";
    $toSign = implode("\n", [
        'AWS4-HMAC-SHA256',
        $now,
        $scope,
        hash('sha256', $canonicalRequest),
    ]);
    $kDate = hash_hmac('sha256', $date, 'AWS4' . $secret, true);
    $kRegion = hash_hmac('sha256', $region, $kDate, true);
    $kService = hash_hmac('sha256', $service, $kRegion, true);
    $kSigning = hash_hmac('sha256', 'aws4_request', $kService, true);
    $signature = hash_hmac('sha256', $toSign, $kSigning);

    return [
        'Host' => $host,
        'x-amz-content-sha256' => $payload,
        'x-amz-date' => $now,
        'Authorization' => "AWS4-HMAC-SHA256 Credential=$key/$scope, SignedHeaders=$names, Signature=$signature",
    ];
}

/**
 * The S3 API: a bucket, an object, and the object read back. Works against the
 * s3 profile and against the S3 of the aws profile.
 */
function s3_round_trip(string $endpoint, string $key, string $secret, string $label): void
{
    $bucket = 'laser-smoke';
    $body = 'laserstack';
    $url = "$endpoint/$bucket";
    [$status, $answer] = request('PUT', $url, sigv4('PUT', $url, 's3', $key, $secret));
    // 200 on the first run, 409 when the bucket of an earlier run is still there
    if ($status !== 200 && $status !== 409) {
        fail("$label: putting the bucket answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    $url = "$endpoint/$bucket/hello.txt";
    [$status, $answer] = request('PUT', $url, sigv4('PUT', $url, 's3', $key, $secret, $body), $body);
    if ($status !== 200) {
        fail("$label: putting the object answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    [$status, $answer] = request('GET', $url, sigv4('GET', $url, 's3', $key, $secret));
    if ($status !== 200 || $answer !== $body) {
        fail("$label: reading the object answered $status with '$answer'");
    }
}

/**
 * The queue of the aws profile: the shape a project uses through
 * aws/aws-sdk-php, over the query protocol of SQS.
 */
function sqs_round_trip(string $endpoint, string $key, string $secret): void
{
    $url = "$endpoint/";
    $form = ['Content-Type' => 'application/x-www-form-urlencoded'];
    $body = 'Action=CreateQueue&QueueName=laser-smoke&Version=2012-11-05';
    $signed = sigv4('POST', $url, 'sqs', $key, $secret, $body);
    [$status, $answer] = request('POST', $url, $form + $signed, $body);
    if ($status !== 200 || !preg_match('#<QueueUrl>([^<]+)</QueueUrl>#', $answer, $match)) {
        fail("aws: creating the queue answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    $queue = html_entity_decode($match[1]);
    $body = 'Action=SendMessage&Version=2012-11-05&QueueUrl=' . rawurlencode($queue) . '&MessageBody=laserstack';
    [$status, $answer] = request('POST', $url, $form + sigv4('POST', $url, 'sqs', $key, $secret, $body), $body);
    if ($status !== 200) {
        fail("aws: sending the message answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    $body = 'Action=ReceiveMessage&Version=2012-11-05&QueueUrl=' . rawurlencode($queue);
    [$status, $answer] = request('POST', $url, $form + sigv4('POST', $url, 'sqs', $key, $secret, $body), $body);
    if ($status !== 200 || strpos($answer, '<Body>laserstack</Body>') === false) {
        fail("aws: the message did not come back ($status): " . substr(strip_tags($answer), 0, 120));
    }
}

/**
 * The Cloud Storage JSON API of the gcs profile.
 */
function gcs_round_trip(string $endpoint): void
{
    $bucket = 'laser-smoke';
    // the emulator accepts any bearer token; a real SDK takes its token from
    // the environment of a project, which is what STORAGE_EMULATOR_HOST sets up
    $auth = ['Authorization' => 'Bearer laser'];
    $body = json_encode(['name' => $bucket]);
    [$status, $answer] = request(
        'POST',
        "$endpoint/storage/v1/b?project=laser",
        $auth + ['Content-Type' => 'application/json'],
        $body
    );
    if ($status !== 200 && $status !== 409) {
        fail("gcs: creating the bucket answered $status: " . substr($answer, 0, 120));
    }
    $body = 'laserstack';
    [$status, $answer] = request(
        'POST',
        "$endpoint/upload/storage/v1/b/$bucket/o?uploadType=media&name=hello.txt",
        $auth + ['Content-Type' => 'text/plain'],
        $body
    );
    if ($status !== 200) {
        fail("gcs: uploading the object answered $status: " . substr($answer, 0, 120));
    }
    [$status, $answer] = request('GET', "$endpoint/storage/v1/b/$bucket/o/hello.txt?alt=media", $auth);
    if ($status !== 200 || $answer !== $body) {
        fail("gcs: reading the object answered $status with '$answer'");
    }
}

/**
 * The blob service of Azurite, with the development account of the emulator and
 * the SharedKey signature its SDKs use.
 *
 * The URL of the emulator carries the account name, and Azure signs the resource
 * with the account in front of that path, so the name appears twice in the
 * signature: /devstoreaccount1/devstoreaccount1/<container>. Every x-ms- header
 * takes part in it, and the length of an empty body is the empty string.
 */
function azure_round_trip(string $endpoint): void
{
    $account = 'devstoreaccount1';
    $key = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==';
    $version = '2021-08-06';
    $container = 'laser-smoke';
    $blob = 'hello.txt';
    $body = 'laserstack';

    // one request of the blob service: the path carries its query, and the
    // headers are the ones the signature covers
    $azure = function (string $method, string $path, string $contentType = '', array $msHeaders = [], string $body = '') use ($endpoint, $account, $key, $version): array {
        $signed = $msHeaders;
        $signed['x-ms-date'] = gmdate('D, d M Y H:i:s \G\M\T');
        $signed['x-ms-version'] = $version;
        ksort($signed);
        $canonical = '';
        foreach ($signed as $name => $value) {
            $canonical .= strtolower($name) . ':' . $value . "\n";
        }
        [$pathOnly, $query] = array_pad(explode('?', $path, 2), 2, '');
        $resource = '/' . $account . $pathOnly;
        foreach ($query === '' ? [] : explode('&', $query) as $field) {
            [$name, $value] = array_pad(explode('=', $field, 2), 2, '');
            $resource .= "\n" . strtolower($name) . ':' . rawurldecode($value);
        }
        $length = $body === '' ? '' : (string) strlen($body);
        $toSign = implode("\n", [$method, '', '', $length, '', $contentType, '', '', '', '', '', ''])
            . "\n" . $canonical . $resource;
        $headers = $signed + ['Authorization' => 'SharedKey ' . $account . ':'
            . base64_encode(hash_hmac('sha256', $toSign, base64_decode($key), true))];
        if ($contentType !== '') {
            $headers['Content-Type'] = $contentType;
        }

        return request($method, $endpoint . $path, $headers, $body === '' ? null : $body);
    };

    [$status, $answer] = $azure('PUT', "/$account/$container?restype=container");
    if ($status !== 201 && $status !== 409) {
        fail("azure: creating the container answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    [$status, $answer] = $azure('PUT', "/$account/$container/$blob", 'text/plain', ['x-ms-blob-type' => 'BlockBlob'], $body);
    if ($status !== 201) {
        fail("azure: putting the blob answered $status: " . substr(strip_tags($answer), 0, 120));
    }
    [$status, $answer] = $azure('GET', "/$account/$container/$blob");
    if ($status !== 200 || $answer !== $body) {
        fail("azure: reading the blob answered $status with '$answer'");
    }
}

// a switch and not a match: the 7.4 images of the stack run this file too
switch ($service) {
    case 's3':
        s3_round_trip(
            getenv('S3_ENDPOINT') ?: 'http://s3:9000',
            getenv('S3_ACCESS_KEY') ?: 'laser',
            getenv('S3_SECRET_KEY') ?: 'laser',
            's3'
        );
        break;
    case 'aws':
        // any credentials work on the emulator, and that is the contract of a
        // local AWS: the SDK of a project keeps its own access key handling.
        // The S3 API of the aws profile answers on the same port as its queues.
        $endpoint = getenv('AWS_ENDPOINT') ?: 'http://aws:4566';
        s3_round_trip($endpoint, 'test', 'test', 'aws');
        sqs_round_trip($endpoint, 'test', 'test');
        break;
    case 'gcs':
        gcs_round_trip(getenv('GCS_ENDPOINT') ?: 'http://gcs:4443');
        break;
    case 'azure':
        azure_round_trip(getenv('AZURE_ENDPOINT') ?: 'http://azure:10000');
        break;
    default:
        fail("usage: php cloud.php s3|aws|gcs|azure (got '$service')");
}

echo "ok $service\n";
