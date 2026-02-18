<?php
// Database configuration
$db_host = getenv('DB_HOST') ?: 'localhost';
$db_name = getenv('DB_NAME') ?: 'cruddb';
$db_user = getenv('DB_USER') ?: 'admin';
$db_pass = getenv('DB_PASS') ?: 'password';
$memcache_host = getenv('MEMCACHE_HOST') ?: 'localhost';

// Connect to Memcached
$memcache = new Memcached();
$memcache->addServer($memcache_host, 11211);
$cache_key = 'items_list';

// Connect to database
try {
    $pdo = new PDO("mysql:host=$db_host;dbname=$db_name", $db_user, $db_pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    $db_error = $e->getMessage();
}

// Handle CRUD operations
$message = '';
$show_valid_only = isset($_GET['valid_only']) && $_GET['valid_only'] == '1';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        switch ($_POST['action']) {
            case 'create':
                $valid = isset($_POST['valid_service']) ? 1 : 0;
                $stmt = $pdo->prepare("INSERT INTO items (name, description, valid_service) VALUES (?, ?, ?)");
                $stmt->execute([$_POST['name'], $_POST['description'], $valid]);
                $memcache->delete($cache_key);
                $memcache->delete($cache_key . '_valid');
                $message = "✅ Item created successfully!";
                break;
            case 'update':
                $valid = isset($_POST['valid_service']) ? 1 : 0;
                $stmt = $pdo->prepare("UPDATE items SET name = ?, description = ?, valid_service = ? WHERE id = ?");
                $stmt->execute([$_POST['name'], $_POST['description'], $valid, $_POST['id']]);
                $memcache->delete($cache_key);
                $memcache->delete($cache_key . '_valid');
                $message = "✅ Item updated successfully!";
                break;
            case 'delete':
                $stmt = $pdo->prepare("DELETE FROM items WHERE id = ?");
                $stmt->execute([$_POST['id']]);
                $memcache->delete($cache_key);
                $memcache->delete($cache_key . '_valid');
                $message = "✅ Item deleted successfully!";
                break;
        }
    }
}

// Fetch items with caching and timing
$items = [];
$cache_hit = false;
$response_time = 0;

if (isset($pdo)) {
    $start_time = microtime(true);
    
    $current_cache_key = $show_valid_only ? $cache_key . '_valid' : $cache_key;
    $items = $memcache->get($current_cache_key);
    
    if ($items === false) {
        $query = $show_valid_only ? "SELECT * FROM items WHERE valid_service = 1 ORDER BY id DESC" : "SELECT * FROM items ORDER BY id DESC";
        $stmt = $pdo->query($query);
        $items = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $memcache->set($current_cache_key, $items, 300);
        $cache_hit = false;
    } else {
        $cache_hit = true;
    }
    
    $response_time = round((microtime(true) - $start_time) * 1000, 2);
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS RDS CRUD Service</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            padding: 40px;
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }
        .message {
            background: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #28a745;
        }
        .error {
            background: #f8d7da;
            color: #721c24;
            border-left-color: #dc3545;
        }
        .form-section {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 30px;
            border-left: 4px solid #667eea;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 5px;
        }
        input, textarea {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            box-sizing: border-box;
        }
        button {
            background: #667eea;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
        }
        button:hover {
            background: #5568d3;
        }
        .items-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        .items-table th {
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
        }
        .items-table td {
            padding: 12px;
            border-bottom: 1px solid #ddd;
        }
        .items-table tr:hover {
            background: #f8f9fa;
        }
        .btn-delete {
            background: #dc3545;
            padding: 5px 10px;
            font-size: 14px;
        }
        .btn-delete:hover {
            background: #c82333;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #666;
            font-size: 14px;
        }
        .timer {
            background: #fff3cd;
            color: #856404;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #ffc107;
            font-weight: bold;
        }
        .filter-section {
            background: #e7f3ff;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #2196F3;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🗄️ AWS RDS + Memcached CRUD Service</h1>
        
        <?php if ($message): ?>
            <div class="message"><?= htmlspecialchars($message) ?></div>
        <?php endif; ?>
        
        <?php if ($cache_hit): ?>
            <div class="message">⚡ Data loaded from Memcached cache</div>
        <?php endif; ?>
        
        <div class="timer">
            ⏱️ Response Time: <?= $response_time ?> ms | Source: <?= $cache_hit ? 'Memcached Cache' : 'MySQL Database' ?>
        </div>
        
        <div class="filter-section">
            <strong>🔍 Filter:</strong>
            <a href="?" style="margin: 0 10px; color: <?= !$show_valid_only ? '#667eea' : '#666' ?>; font-weight: <?= !$show_valid_only ? 'bold' : 'normal' ?>;">All Items</a> |
            <a href="?valid_only=1" style="margin: 0 10px; color: <?= $show_valid_only ? '#667eea' : '#666' ?>; font-weight: <?= $show_valid_only ? 'bold' : 'normal' ?>;">Valid AWS Services Only</a>
        </div>
        
        <?php if (isset($db_error)): ?>
            <div class="message error">❌ Database Error: <?= htmlspecialchars($db_error) ?></div>
        <?php else: ?>
        
        <div class="form-section">
            <h3>➕ Create New Item</h3>
            <form method="POST">
                <input type="hidden" name="action" value="create">
                <div class="form-group">
                    <label>Name:</label>
                    <input type="text" name="name" required>
                </div>
                <div class="form-group">
                    <label>Description:</label>
                    <textarea name="description" rows="3" required></textarea>
                </div>
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="valid_service" value="1">
                        Valid AWS Service
                    </label>
                </div>
                <button type="submit">Create Item</button>
            </form>
        </div>
        
        <h3>📋 Items List</h3>
        <?php if (count($items) > 0): ?>
            <table class="items-table">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Name</th>
                        <th>Description</th>
                        <th>Valid AWS</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($items as $item): ?>
                    <tr>
                        <td><?= htmlspecialchars($item['id']) ?></td>
                        <td><?= htmlspecialchars($item['name']) ?></td>
                        <td><?= htmlspecialchars($item['description']) ?></td>
                        <td><?= $item['valid_service'] ? '✅ Yes' : '❌ No' ?></td>
                        <td>
                            <form method="POST" style="display:inline;">
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="id" value="<?= $item['id'] ?>">
                                <button type="submit" class="btn-delete" onclick="return confirm('Delete this item?')">Delete</button>
                            </form>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        <?php else: ?>
            <p>No items found. Create your first item above!</p>
        <?php endif; ?>
        
        <?php endif; ?>
        
        <div class="footer">
            <strong>⚠️ Security Notice:</strong> This is a basic sample with minimum security. Users are accessing the service host directly. 
            Although the DB security group does not allow traffic from the internet, the database is not in a private subnet, 
            which would offer an extra layer of data protection.
            <br><br>
            AWS CloudChaps Training - RDS + Memcached CRUD Demo
        </div>
    </div>
</body>
</html>
