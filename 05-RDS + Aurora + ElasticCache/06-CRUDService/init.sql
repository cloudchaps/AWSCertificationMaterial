-- Create database
CREATE DATABASE IF NOT EXISTS cruddb;
USE cruddb;

-- Create items table
CREATE TABLE IF NOT EXISTS items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO items (name, description) VALUES
('Sample Item 1', 'This is a sample item stored in AWS RDS'),
('Sample Item 2', 'Another example item demonstrating CRUD operations'),
('Sample Item 3', 'Testing database connectivity with Aurora/RDS');
