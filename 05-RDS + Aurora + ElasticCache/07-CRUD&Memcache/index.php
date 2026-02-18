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
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        switch ($_POST['action']) {
            case 'create':
                $stmt = $pdo->prepare("INSERT INTO items (name, description) VALUES (?, ?)");
                $stmt->execute([$_POST['name'], $_POST['description']]);
                $memcache->delete($cache_key);
                $message = "✅ Item created successfully!";
                break;
            case 'update':
                $stmt = $pdo->prepare("UPDATE items SET name = ?, description = ? WHERE id = ?");
                $stmt->execute([$_POST['name'], $_POST['description'], $_POST['id']]);
                $memcache->delete($cache_key);
                $message = "✅ Item updated successfully!";
                break;
            case 'delete':
                $stmt = $pdo->prepare("DELETE FROM items WHERE id = ?");
                $stmt->execute([$_POST['id']]);
                $memcache->delete($cache_key);
                $message = "✅ Item deleted successfully!";
                break;
        }
    }
}

// Fetch all items with caching
$items = [];
$cache_hit = false;
if (isset($pdo)) {
    $items = $memcache->get($cache_key);
    if ($items === false) {
        $stmt = $pdo->query("SELECT * FROM items ORDER BY id DESC");
        $items = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $memcache->set($cache_key, $items, 300);
        $cache_hit = false;
    } else {
        $cache_hit = true;
    }
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
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($items as $item): ?>
                    <tr>
                        <td><?= htmlspecialchars($item['id']) ?></td>
                        <td><?= htmlspecialchars($item['name']) ?></td>
                        <td><?= htmlspecialchars($item['description']) ?></td>
                        <td>
                            <button onclick="editItem(<?= $item['id'] ?>, '<?= htmlspecialchars($item['name'], ENT_QUOTES) ?>', '<?= htmlspecialchars($item['description'], ENT_QUOTES) ?>')" style="background: #ffc107; margin-right: 5px;">Edit</button>
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
    <script>
    function editItem(id, name, description) {
        document.querySelector('input[name="action"]').value = 'update';
        document.querySelector('input[name="name"]').value = name;
        document.querySelector('textarea[name="description"]').value = description;
        
        let form = document.querySelector('.form-section form');
        if (!document.querySelector('input[name="id"]')) {
            let idInput = document.createElement('input');
            idInput.type = 'hidden';
            idInput.name = 'id';
            form.appendChild(idInput);
        }
        document.querySelector('input[name="id"]').value = id;
        document.querySelector('.form-section h3').textContent = '✏️ Update Item';
        document.querySelector('.form-section button').textContent = 'Update Item';
        window.scrollTo(0, 0);
    }
    </script>
</body>
</html>
