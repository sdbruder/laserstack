<?php

/**
 * The Laser Stack dashboard.
 *
 * Laser Stack serves every project of the projects directory under one suffix,
 * and this checkout is one of those projects, so this page is reached like any
 * other project: the catch-all vhost needs only public/index.php to exist.
 *
 * The page is read-only. It writes nothing, runs no command and prints no
 * credential: it reports the PHP it runs on, the projects the stack serves, the
 * services of the profile that answer, and the versions this checkout supports.
 */

declare(strict_types=1);

$root = dirname(__DIR__);
$projectsDir = (string) (getenv('PROJECTS_DIR') ?: '/var/www');
$suffix = suffix();
$host = (string) ($_SERVER['HTTP_HOST'] ?? '');
$self = basename($root);

// the page reloads itself every this many seconds; ?refresh=0 turns it off
$refreshSeconds = 10;

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

/**
 * The suffix the stack serves under. The environment of the app container
 * carries it, and the vhost nginx rendered at start-up carries it too, which is
 * the copy that decides the answer. A pool of the newer images clears the
 * environment, so the rendered file is the fallback that always works.
 */
function suffix(): string
{
    $fromEnvironment = trim((string) getenv('SUFFIX'), '.');
    if ($fromEnvironment !== '') {
        return $fromEnvironment;
    }
    $files = [
        '/etc/nginx/sites-enabled/multiProjectLaravel.conf',
        '/etc/nginx/http.d/multiProjectLaravel.conf.template',
    ];
    foreach ($files as $file) {
        $config = @file_get_contents($file);
        if ($config !== false && preg_match('/\\.([A-Za-z0-9.\-]+)\$"/', $config, $match) === 1) {
            return $match[1];
        }
    }

    return 'localdev.it';
}

/** One TCP connect: the cheapest proof that a service of the profile is up. */
function probe(string $host, int $port, float $timeout = 0.4): array
{
    $start = microtime(true);
    $socket = @fsockopen($host, $port, $errno, $errstr, $timeout);
    $ms = (int) round((microtime(true) - $start) * 1000);
    if ($socket === false) {
        return ['up' => false, 'ms' => null];
    }
    fclose($socket);

    return ['up' => true, 'ms' => $ms];
}

/** The subdirectory names of a config directory, in version order. */
function versions(string $base): array
{
    $found = [];
    foreach (glob($base . '/*', GLOB_ONLYDIR) ?: [] as $dir) {
        $found[] = basename($dir);
    }
    sort($found, SORT_NATURAL);

    return $found;
}

/**
 * The config directory of the running PHP. Alpine names the directory of the
 * 8.0 series config/php8, and 7.4 is config/php74.
 */
function php_config_dir(string $version): string
{
    $parts = explode('.', $version);
    $digits = ($parts[0] ?? '') . ($parts[1] ?? '');
    if ($digits === '80' || $digits === '8') {
        return 'php8';
    }

    return 'php' . $digits;
}

/**
 * The profiles the .env of the checkout enables, or null when that file cannot be
 * read: a service of an enabled profile that does not answer is a fault, a
 * service of a profile that is off is simply not running.
 */
function enabledProfiles(string $envFile): ?array
{
    $file = @file_get_contents($envFile);
    if ($file === false) {
        return null;
    }
    if (preg_match('/^PROFILES=(.*)$/m', $file, $match) !== 1) {
        return [];
    }
    $names = [];
    foreach (explode(',', trim($match[1], " \t\"'")) as $name) {
        $name = trim($name);
        if ($name !== '') {
            $names[] = $name;
        }
    }

    return $names;
}

$services = [
    ['label' => 'MySQL', 'host' => 'db', 'port' => 3306, 'engine' => 'mysql', 'profile' => 'mysql'],
    ['label' => 'MariaDB', 'host' => 'mariadb', 'port' => 3306, 'engine' => 'mariadb', 'profile' => 'mariadb'],
    ['label' => 'PostgreSQL', 'host' => 'postgres', 'port' => 5432, 'engine' => null, 'profile' => 'postgres'],
    ['label' => 'redis', 'host' => 'redis', 'port' => 6379, 'engine' => null, 'profile' => 'redis'],
    ['label' => 'memcached', 'host' => 'memcached', 'port' => 11211, 'engine' => null, 'profile' => 'memcached'],
    ['label' => 'Elasticsearch', 'host' => 'elasticsearch', 'port' => 9200, 'engine' => null, 'profile' => 'elasticsearch'],
];

$profiles = enabledProfiles($root . '/.env');

// MySQL and MariaDB share the db alias, so a port that answers does not say
// which engine is behind it. The mariadb service is the only one that answers to
// its own name, so that name decides which of the two the stack started.
$sqlEngine = probe('mariadb', 3306)['up'] ? 'mariadb' : (probe('db', 3306)['up'] ? 'mysql' : null);

// The server version of the profile, when one answers. The credentials come
// from the environment of the app container and are never printed.
$serverVersion = null;
$clientVersion = null;
$serverError = null;
if (extension_loaded('pdo_mysql')) {
    $candidates = [
        ['MYSQL_USER', 'MYSQL_PASSWORD', 'MYSQL_DATABASE'],
        ['MARIADB_USER', 'MARIADB_PASSWORD', 'MARIADB_DATABASE'],
    ];
    foreach ($candidates as [$userVar, $passVar, $nameVar]) {
        $user = getenv($userVar);
        if ($user === false || $user === '') {
            continue;
        }
        try {
            $dsn = 'mysql:host=db;port=3306;dbname=' . (getenv($nameVar) ?: 'mysql');
            $pdo = new PDO($dsn, $user, (string) getenv($passVar), [
                PDO::ATTR_TIMEOUT => 2,
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            ]);
            $serverVersion = (string) $pdo->query('select version()')->fetchColumn();
            $clientVersion = (string) $pdo->getAttribute(PDO::ATTR_CLIENT_VERSION);
            break;
        } catch (Throwable $error) {
            $serverError = $error->getMessage();
        }
    }
}

$projects = [];
foreach (scandir($projectsDir) ?: [] as $entry) {
    if ($entry === '.' || $entry === '..' || $entry[0] === '.') {
        continue;
    }
    $path = $projectsDir . '/' . $entry;
    if (!is_dir($path)) {
        continue;
    }
    $projects[] = [
        'name' => $entry,
        'index' => is_file($path . '/public/index.php'),
        'public' => is_dir($path . '/public'),
        'vhost' => is_file('/etc/nginx/http.d/' . $entry . '.conf'),
        'self' => $entry === $self,
    ];
}

$phpVersion = PHP_VERSION;
$phpDir = php_config_dir($phpVersion);
$phpSeries = array_values(array_filter(
    versions($root . '/config'),
    static fn (string $name): bool => strpos($name, 'php') === 0
));
$engines = [];
foreach (['mysql', 'mariadb', 'postgres', 'redis', 'elasticsearch'] as $engine) {
    $engines[$engine] = versions($root . '/config/' . $engine);
}

$extensions = [
    'pdo_mysql', 'pdo_pgsql', 'mysqli', 'sqlite3', 'redis', 'memcached', 'mongodb',
    'opcache', 'xdebug', 'gd', 'imagick', 'intl', 'zip', 'bcmath', 'sodium', 'pcntl',
];

$changelog = @file($root . '/CHANGELOG.md', FILE_IGNORE_NEW_LINES) ?: [];
$changelogHead = array_slice($changelog, 0, 24);
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Laser Stack</title>
<style>
:root { --fg:#1b1f23; --muted:#6a737d; --bg:#f6f7f9; --card:#fff; --line:#e1e4e8; --ok:#1a7f37; --off:#b42318; --accent:#6f42c1; }
@media (prefers-color-scheme: dark) { :root { --fg:#e6edf3; --muted:#8b949e; --bg:#0d1117; --card:#161b22; --line:#30363d; --ok:#3fb950; --off:#f85149; --accent:#a371f7; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
main { width:100%; padding:20px clamp(16px,2.5vw,44px) 56px; }
header { display:flex; flex-wrap:wrap; align-items:baseline; justify-content:space-between; gap:6px 24px; }
h1 { font-size:30px; margin:0; letter-spacing:-.02em; }
h2 { font-size:14px; text-transform:uppercase; letter-spacing:.08em; color:var(--muted); margin:0 0 12px; }
p.lead { color:var(--muted); margin:8px 0 0; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(min(100%,248px),1fr)); gap:14px; margin-top:18px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; }
.card.wide { grid-column:1/-1; }
.card.wide2 { grid-column:span 2; }
@media (max-width:860px) { .card.wide2 { grid-column:auto; } }
.up, .down { white-space:nowrap; }
td code { overflow-wrap:anywhere; }
table { width:100%; border-collapse:collapse; }
td, th { text-align:left; padding:5px 0; border-bottom:1px solid var(--line); font-size:14px; vertical-align:top; }
td:first-child { white-space:nowrap; padding-right:16px; color:var(--muted); }
tr:last-child td { border-bottom:0; }
code, pre { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:13px; }
pre { background:transparent; margin:0; white-space:pre-wrap; color:var(--muted); }
a { color:var(--accent); text-decoration:none; }
a:hover { text-decoration:underline; }
.up { color:var(--ok); }
.down { color:var(--off); }
.chips { display:flex; flex-wrap:wrap; gap:6px; }
.chip { border:1px solid var(--line); border-radius:999px; padding:2px 10px; font-size:13px; }
.chip.on { border-color:var(--ok); color:var(--ok); }
.chip.off { color:var(--muted); opacity:.65; }
.muted { color:var(--muted); }
.note { color:var(--muted); font-size:13px; margin:10px 0 0; }
ul.projects { list-style:none; margin:0; padding:0; display:grid; grid-template-columns:repeat(auto-fill,minmax(11.5rem,1fr)); gap:6px; }
ul.projects li { display:flex; align-items:baseline; gap:6px; padding:4px 9px; border:1px solid var(--line); border-radius:8px; font-size:14px; min-width:0; }
ul.projects li a { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
ul.projects li .tag { flex:0 0 auto; }
.tag { font-size:11px; text-transform:uppercase; letter-spacing:.06em; color:var(--muted); border:1px solid var(--line); border-radius:4px; padding:1px 6px; }
footer { margin-top:26px; color:var(--muted); font-size:13px; }
</style>
</head>
<body>
<main>
    <header>
        <h1>Laser Stack</h1>
        <p class="lead">
            Served from <code><?= e($host !== '' ? $host : $self . '.' . $suffix) ?></code>
            by the container of the stack, one of the projects it serves.
        </p>
    </header>

    <div class="grid">
        <section class="card">
            <h2>This container</h2>
            <table>
                <tr><td>PHP</td><td><strong><?= e($phpVersion) ?></strong></td></tr>
                <tr><td>Config directory</td><td><code>config/<?= e($phpDir) ?></code><?= in_array($phpDir, $phpSeries, true) ? '' : ' <span class="muted">(not in the checkout)</span>' ?></td></tr>
                <tr><td>SAPI</td><td><?= e(PHP_SAPI) ?></td></tr>
                <tr><td>Checkout</td><td><code><?= e($root) ?></code></td></tr>
                <tr><td>Suffix</td><td><code><?= e($suffix) ?></code></td></tr>
            </table>
            <p class="note">The PHP series is the image tag <code>PHP_VERSION</code>: edit <code>.env</code> and run <code>laser up -d</code> to change it.</p>
        </section>

        <section class="card wide2">
            <h2>Services</h2>
            <table>
                <?php foreach ($services as $service): ?>
                    <?php
                    $state = probe($service['host'], $service['port']);
                    // the two SQL engines share the db alias: only the one the
                    // stack started is running, whatever the port says
                    $up = $service['engine'] === null ? $state['up'] : $sqlEngine === $service['engine'];
                    // the checkout says whether it should be running at all
                    $expected = $profiles === null || in_array($service['profile'], $profiles, true);
                    ?>
                    <tr>
                        <td><?= e($service['label']) ?></td>
                        <td><code><?= e($service['host'] . ':' . $service['port']) ?></code></td>
                        <td>
                            <?php if ($up): ?>
                                <span class="up">up</span> <span class="muted"><?= e((string) $state['ms']) ?> ms</span>
                            <?php elseif ($expected): ?>
                                <span class="down">no answer</span>
                            <?php else: ?>
                                <span class="muted">not running</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </table>
            <p class="note">A service of a profile in <code>PROFILES</code> that does not answer reads <span class="down">no answer</span>; a service whose profile is off reads <span class="muted">not running</span>. MySQL and MariaDB share the <code>db</code> alias, so the one that answers to its own name is the one running.</p>
        </section>

        <section class="card">
            <h2>Database</h2>
            <?php if ($serverVersion !== null): ?>
                <table>
                    <tr><td>Server</td><td><strong><?= e($serverVersion) ?></strong></td></tr>
                    <tr><td>Client</td><td><code><?= e($clientVersion ?? 'pdo_mysql') ?></code></td></tr>
                </table>
            <?php else: ?>
                <p class="muted">No database answers. <?= e($serverError ?? '') ?></p>
                <p class="note">That is expected when the profile of this stack has no database.</p>
            <?php endif; ?>
        </section>

        <section class="card">
            <h2>Version directories</h2>
            <table>
                <tr><td>PHP</td><td><code><?= e(implode(', ', $phpSeries)) ?></code></td></tr>
                <?php foreach ($engines as $engine => $list): ?>
                    <tr><td><?= e($engine) ?></td><td><code><?= e($list === [] ? 'image only' : implode(', ', $list)) ?></code></td></tr>
                <?php endforeach; ?>
                <tr><td>memcached</td><td><code>image only</code></td></tr>
            </table>
            <p class="note">Each name is a directory under <code>config/</code> and a version the stack can select by environment variable.</p>
        </section>

        <section class="card wide">
            <h2>PHP extensions</h2>
            <div class="chips">
                <?php foreach ($extensions as $extension): ?>
                    <span class="chip <?= extension_loaded($extension) ? 'on' : 'off' ?>"><?= e($extension) ?></span>
                <?php endforeach; ?>
            </div>
        </section>

        <section class="card wide">
            <h2>Projects served</h2>
            <ul class="projects">
                <?php foreach ($projects as $project): ?>
                    <li>
                        <a href="<?= e('//' . $project['name'] . '.' . $suffix . '/') ?>" target="_blank" rel="noopener noreferrer" title="<?= e($project['name'] . '.' . $suffix) ?>"><?= e($project['name']) ?></a>
                        <?php if ($project['self']): ?><span class="tag">this page</span><?php endif; ?>
                        <?php if (!$project['public']): ?><span class="tag">no public/</span><?php endif; ?>
                        <?php if ($project['vhost']): ?><span class="tag">own vhost</span><?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
            <p class="note"><code><?= e($projectsDir) ?></code>, <code>PROJECTS_DIRECTORY</code> in <code>.env</code>. Add a directory with a <code>public/index.php</code>, run <code>laser scan</code>, and it answers on its own name.</p>
        </section>

        <section class="card wide">
            <h2>What is new</h2>
            <pre><?= e(implode("\n", $changelogHead)) ?></pre>
        </section>
    </div>

    <footer>
        <a href="https://localdev.it/laserstack/" target="_blank" rel="noopener noreferrer">Documentation</a> &middot;
        <a href="https://github.com/sdbruder/laserstack" target="_blank" rel="noopener noreferrer">Repository</a> &middot;
        <a href="https://localdev.it/laserstack/compare.html" target="_blank" rel="noopener noreferrer">Comparison</a>
        <p class="note">Read-only status page: it reads the checkout, opens a socket to each service and nothing else. It reloads itself every <span id="refresh-every">few</span> seconds, keeping your place on the page; append <code>?refresh=0</code> to stop that.</p>
    </footer>
</main>
<script>
  (function () {
    var seconds = Number(new URLSearchParams(location.search).get('refresh') || <?= (int) $refreshSeconds ?>);
    var label = document.getElementById('refresh-every');
    if (label) { label.textContent = seconds ? String(seconds) : '0'; }
    if (!seconds || seconds < 2) { return; }
    var key = 'laserstack-dashboard-scroll';
    var saved = sessionStorage.getItem(key);
    if (saved !== null) { window.scrollTo(0, Number(saved)); sessionStorage.removeItem(key); }
    setInterval(function () {
      if (document.hidden) { return; }
      sessionStorage.setItem(key, String(window.scrollY));
      location.reload();
    }, seconds * 1000);
  })();
</script>
</body>
</html>
