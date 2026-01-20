-- ============================================
-- LOGISTICS PLATFORM DATABASE INITIALIZATION
-- VERSION: 2.0 (Secure)
-- ============================================

-- Drop database if exists (for clean setup)
DROP DATABASE IF EXISTS logistics_platform;

-- Create database
CREATE DATABASE logistics_platform 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE logistics_platform;

-- ============================================
-- TABLE CREATION
-- ============================================

-- Users table for authentication and authorization
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('admin', 'manager', 'staff', 'customer') DEFAULT 'staff',
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    phone VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_role (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Customers table (can also be linked to users table)
CREATE TABLE customers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NULL, -- Optional link to users table for customer portal access
    company_name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50) DEFAULT 'USA',
    postal_code VARCHAR(20),
    customer_type ENUM('individual', 'business', 'corporate') DEFAULT 'business',
    account_balance DECIMAL(10,2) DEFAULT 0.00,
    credit_limit DECIMAL(10,2) DEFAULT 10000.00,
    payment_terms VARCHAR(50) DEFAULT 'Net 30',
    is_active BOOLEAN DEFAULT TRUE,
    tax_id VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_company_name (company_name),
    INDEX idx_email (email),
    INDEX idx_customer_type (customer_type),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shipments table (main table for all shipments)
CREATE TABLE shipments (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tracking_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT NOT NULL,
    shipment_type ENUM('express', 'standard', 'fragile', 'oversized', 'hazardous') DEFAULT 'standard',
    status ENUM(
        'pending',
        'pickup_scheduled',
        'in_transit',
        'at_warehouse',
        'out_for_delivery',
        'delivered',
        'delayed',
        'cancelled',
        'returned',
        'lost'
    ) DEFAULT 'pending',
    
    -- Origin information
    origin_name VARCHAR(100),
    origin_address TEXT,
    origin_city VARCHAR(50),
    origin_state VARCHAR(50),
    origin_country VARCHAR(50),
    origin_postal_code VARCHAR(20),
    origin_phone VARCHAR(20),
    
    -- Destination information
    destination_name VARCHAR(100),
    destination_address TEXT,
    destination_city VARCHAR(50),
    destination_state VARCHAR(50),
    destination_country VARCHAR(50),
    destination_postal_code VARCHAR(20),
    destination_phone VARCHAR(20),
    recipient_name VARCHAR(100),
    recipient_phone VARCHAR(20),
    
    -- Package details
    weight DECIMAL(8,2) COMMENT 'Weight in kg',
    dimensions VARCHAR(50) COMMENT 'Format: LxWxH in cm',
    package_count INT DEFAULT 1,
    declared_value DECIMAL(10,2) DEFAULT 0.00,
    insurance_amount DECIMAL(10,2) DEFAULT 0.00,
    contents_description TEXT,
    
    -- Shipping details
    shipping_cost DECIMAL(10,2),
    tax_amount DECIMAL(10,2) DEFAULT 0.00,
    total_amount DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'USD',
    
    -- Service details
    service_type VARCHAR(50),
    delivery_instructions TEXT,
    special_handling TEXT,
    
    -- Dates
    pickup_date DATETIME,
    estimated_delivery DATETIME,
    actual_delivery DATETIME NULL,
    
    -- Assigned personnel
    assigned_driver_id INT NULL,
    assigned_warehouse_id INT NULL,
    
    -- Payment information
    payment_status ENUM('pending', 'paid', 'partial', 'overdue') DEFAULT 'pending',
    payment_method VARCHAR(50),
    invoice_number VARCHAR(50),
    
    -- Audit fields
    created_by INT NULL,
    updated_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT chk_shipment_weight CHECK (weight > 0),
    CONSTRAINT chk_shipment_dates CHECK (pickup_date <= estimated_delivery),
    
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
    FOREIGN KEY (assigned_driver_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_tracking_number (tracking_number),
    INDEX idx_customer_id (customer_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_estimated_delivery (estimated_delivery),
    INDEX idx_origin_city (origin_city),
    INDEX idx_destination_city (destination_city),
    INDEX idx_payment_status (payment_status),
    INDEX idx_shipments_origin_dest_date (origin_city, destination_city, estimated_delivery),
    INDEX idx_shipments_customer_date (customer_id, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Status History table to track shipment status changes
CREATE TABLE status_history (
    id INT PRIMARY KEY AUTO_INCREMENT,
    shipment_id INT NOT NULL,
    status ENUM(
        'pending',
        'pickup_scheduled',
        'in_transit',
        'at_warehouse',
        'out_for_delivery',
        'delivered',
        'delayed',
        'cancelled',
        'returned',
        'lost'
    ) NOT NULL,
    location VARCHAR(100),
    notes TEXT,
    created_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (shipment_id) REFERENCES shipments(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_shipment_id (shipment_id),
    INDEX idx_created_at (created_at),
    INDEX idx_status (status),
    INDEX idx_status_history_shipment_date (shipment_id, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Warehouses table
CREATE TABLE warehouses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    phone VARCHAR(20),
    email VARCHAR(100),
    manager_id INT NULL,
    capacity_sqft DECIMAL(10,2),
    current_utilization DECIMAL(5,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (manager_id) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_code (code),
    INDEX idx_city (city),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Vehicles table
CREATE TABLE vehicles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    vehicle_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type VARCHAR(50),
    make VARCHAR(50),
    model VARCHAR(50),
    year YEAR,
    capacity_kg DECIMAL(8,2),
    current_location VARCHAR(100),
    status ENUM('available', 'in_use', 'maintenance', 'out_of_service') DEFAULT 'available',
    assigned_driver_id INT NULL,
    last_maintenance_date DATE,
    next_maintenance_date DATE,
    insurance_expiry DATE,
    registration_expiry DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (assigned_driver_id) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_vehicle_number (vehicle_number),
    INDEX idx_status (status),
    INDEX idx_assigned_driver (assigned_driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Invoices table
CREATE TABLE invoices (
    id INT PRIMARY KEY AUTO_INCREMENT,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT NOT NULL,
    shipment_id INT NULL,
    invoice_date DATE NOT NULL,
    due_date DATE NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) DEFAULT 0.00,
    discount_amount DECIMAL(10,2) DEFAULT 0.00,
    total_amount DECIMAL(10,2) NOT NULL,
    amount_paid DECIMAL(10,2) DEFAULT 0.00,
    balance_due DECIMAL(10,2) GENERATED ALWAYS AS (total_amount - amount_paid) STORED,
    status ENUM('draft', 'sent', 'paid', 'overdue', 'cancelled') DEFAULT 'draft',
    payment_method VARCHAR(50),
    payment_date DATE NULL,
    notes TEXT,
    created_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_invoice_dates CHECK (invoice_date <= due_date),
    CONSTRAINT chk_invoice_amount CHECK (total_amount >= 0),
    
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
    FOREIGN KEY (shipment_id) REFERENCES shipments(id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_invoice_number (invoice_number),
    INDEX idx_customer_id (customer_id),
    INDEX idx_status (status),
    INDEX idx_due_date (due_date),
    INDEX idx_invoice_date (invoice_date),
    INDEX idx_invoices_customer_status_date (customer_id, status, due_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Invoice items table
CREATE TABLE invoice_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    invoice_id INT NOT NULL,
    description VARCHAR(255) NOT NULL,
    quantity INT DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    amount DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_invoice_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_invoice_item_price CHECK (unit_price >= 0),
    
    FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
    
    INDEX idx_invoice_id (invoice_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Payments table
CREATE TABLE payments (
    id INT PRIMARY KEY AUTO_INCREMENT,
    payment_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT NOT NULL,
    invoice_id INT NULL,
    payment_date DATE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(50),
    reference_number VARCHAR(100),
    status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'completed',
    notes TEXT,
    created_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_payment_amount CHECK (amount > 0),
    
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_payment_number (payment_number),
    INDEX idx_customer_id (customer_id),
    INDEX idx_invoice_id (invoice_id),
    INDEX idx_payment_date (payment_date),
    INDEX idx_payments_customer_date (customer_id, payment_date DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit Log table
CREATE TABLE audit_log (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NULL,
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id INT NULL,
    old_values JSON NULL,
    new_values JSON NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_user_id (user_id),
    INDEX idx_entity_type (entity_type),
    INDEX idx_created_at (created_at),
    INDEX idx_action (action)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- IMPROVED TRIGGERS
-- ============================================

DELIMITER $$

-- Improved trigger to automatically create status history entry when shipment status changes
CREATE TRIGGER shipment_status_change_trigger 
AFTER UPDATE ON shipments 
FOR EACH ROW 
BEGIN
    IF OLD.status != NEW.status THEN
        -- Get location based on status
        SET @location = CASE 
            WHEN NEW.status = 'in_transit' THEN CONCAT(NEW.origin_city, ' to ', NEW.destination_city)
            WHEN NEW.status = 'at_warehouse' THEN COALESCE((SELECT city FROM warehouses WHERE id = NEW.assigned_warehouse_id), NEW.destination_city)
            WHEN NEW.status = 'out_for_delivery' THEN NEW.destination_city
            WHEN NEW.status = 'delivered' THEN NEW.destination_city
            ELSE COALESCE(NEW.destination_city, NEW.origin_city)
        END;
        
        INSERT INTO status_history (shipment_id, status, location, notes, created_by)
        VALUES (NEW.id, NEW.status, @location,
                CONCAT('Status changed from ', OLD.status, ' to ', NEW.status),
                NEW.updated_by);
    END IF;
END$$

-- Trigger to create initial status history when shipment is created
CREATE TRIGGER shipment_creation_trigger 
AFTER INSERT ON shipments 
FOR EACH ROW 
BEGIN
    INSERT INTO status_history (shipment_id, status, location, notes, created_by)
    VALUES (NEW.id, NEW.status, NEW.origin_city, 'Shipment created', NEW.created_by);
END$$

-- Enhanced trigger for audit logging on user updates
CREATE TRIGGER user_audit_trigger 
AFTER UPDATE ON users 
FOR EACH ROW 
BEGIN
    INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_values, new_values)
    VALUES (
        COALESCE(NEW.updated_by, NEW.id),
        'UPDATE',
        'users',
        NEW.id,
        JSON_OBJECT(
            'username', OLD.username,
            'email', OLD.email,
            'role', OLD.role,
            'first_name', OLD.first_name,
            'last_name', OLD.last_name,
            'is_active', OLD.is_active,
            'updated_at', OLD.updated_at
        ),
        JSON_OBJECT(
            'username', NEW.username,
            'email', NEW.email,
            'role', NEW.role,
            'first_name', NEW.first_name,
            'last_name', NEW.last_name,
            'is_active', NEW.is_active,
            'updated_at', NEW.updated_at
        )
    );
END$$

-- Trigger for audit logging on user creation
CREATE TRIGGER user_creation_trigger 
AFTER INSERT ON users 
FOR EACH ROW 
BEGIN
    INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_values, new_values)
    VALUES (
        NEW.created_by,
        'CREATE',
        'users',
        NEW.id,
        NULL,
        JSON_OBJECT(
            'username', NEW.username,
            'email', NEW.email,
            'role', NEW.role,
            'first_name', NEW.first_name,
            'last_name', NEW.last_name,
            'is_active', NEW.is_active
        )
    );
END$$

DELIMITER ;

-- ============================================
-- IMPROVED STORED PROCEDURES
-- ============================================

DELIMITER $$

-- Improved procedure to generate tracking number with better sequence handling
CREATE PROCEDURE generate_tracking_number(OUT tracking_num VARCHAR(50))
BEGIN
    DECLARE date_part CHAR(6);
    DECLARE seq_num INT;
    DECLARE max_tracking VARCHAR(50);
    
    SET date_part = DATE_FORMAT(NOW(), '%y%m%d');
    
    -- Find the maximum tracking number for today
    SELECT MAX(tracking_number) INTO max_tracking
    FROM shipments 
    WHERE tracking_number LIKE CONCAT('TRK', date_part, '%');
    
    IF max_tracking IS NULL THEN
        SET seq_num = 1;
    ELSE
        -- Extract numeric part safely
        SET seq_num = CAST(SUBSTRING(max_tracking, 8) AS UNSIGNED) + 1;
    END IF;
    
    SET tracking_num = CONCAT('TRK', date_part, LPAD(seq_num, 4, '0'));
END$$

-- Procedure to get shipment statistics with more metrics
CREATE PROCEDURE get_shipment_statistics(
    IN start_date DATE,
    IN end_date DATE,
    OUT total_shipments INT,
    OUT delivered INT,
    OUT pending INT,
    OUT in_transit INT,
    OUT delayed INT,
    OUT revenue DECIMAL(10,2),
    OUT avg_delivery_time DECIMAL(5,2)
)
BEGIN
    -- Total shipments
    SELECT COUNT(*) INTO total_shipments
    FROM shipments
    WHERE DATE(created_at) BETWEEN start_date AND end_date;
    
    -- Delivered shipments
    SELECT COUNT(*) INTO delivered
    FROM shipments
    WHERE status = 'delivered'
    AND DATE(created_at) BETWEEN start_date AND end_date;
    
    -- Pending shipments
    SELECT COUNT(*) INTO pending
    FROM shipments
    WHERE status IN ('pending', 'pickup_scheduled')
    AND DATE(created_at) BETWEEN start_date AND end_date;
    
    -- In transit shipments
    SELECT COUNT(*) INTO in_transit
    FROM shipments
    WHERE status = 'in_transit'
    AND DATE(created_at) BETWEEN start_date AND end_date;
    
    -- Delayed shipments
    SELECT COUNT(*) INTO delayed
    FROM shipments
    WHERE status = 'delayed'
    AND DATE(created_at) BETWEEN start_date AND end_date;
    
    -- Total revenue
    SELECT COALESCE(SUM(total_amount), 0) INTO revenue
    FROM shipments
    WHERE status = 'delivered'
    AND DATE(created_at) BETWEEN start_date AND end_date;
    
    -- Average delivery time (in days)
    SELECT COALESCE(AVG(DATEDIFF(actual_delivery, created_at)), 0) INTO avg_delivery_time
    FROM shipments
    WHERE status = 'delivered'
    AND actual_delivery IS NOT NULL
    AND DATE(created_at) BETWEEN start_date AND end_date;
END$$

-- Improved backup procedure with validation
CREATE PROCEDURE backup_table_data(
    IN p_table_name VARCHAR(64),
    IN p_backup_prefix VARCHAR(50)
)
BEGIN
    DECLARE backup_table VARCHAR(100);
    DECLARE table_exists INT;
    
    -- Validate table name (basic protection against SQL injection)
    IF NOT p_table_name REGEXP '^[a-zA-Z0-9_]+$' THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Invalid table name format';
    END IF;
    
    SET backup_table = CONCAT('backup_', p_backup_prefix, '_', p_table_name);
    
    -- Check if table exists
    SELECT COUNT(*) INTO table_exists
    FROM information_schema.tables 
    WHERE table_schema = DATABASE() 
    AND table_name = p_table_name;
    
    IF table_exists = 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = CONCAT('Table ', p_table_name, ' does not exist');
    END IF;
    
    -- Create backup table
    SET @sql = CONCAT('DROP TABLE IF EXISTS ', backup_table);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    SET @sql = CONCAT('CREATE TABLE ', backup_table, ' LIKE ', p_table_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    SET @sql = CONCAT('INSERT INTO ', backup_table, ' SELECT * FROM ', p_table_name);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    SELECT CONCAT('Backup created: ', backup_table) AS result;
END$$

-- Procedure to securely change user password
CREATE PROCEDURE change_user_password(
    IN p_username VARCHAR(50),
    IN p_new_password_hash VARCHAR(255),
    IN p_changed_by INT
)
BEGIN
    DECLARE user_exists INT;
    DECLARE old_password_hash VARCHAR(255);
    
    -- Check if user exists
    SELECT COUNT(*) INTO user_exists
    FROM users 
    WHERE username = p_username;
    
    IF user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'User does not exist';
    END IF;
    
    -- Get old password for audit
    SELECT password_hash INTO old_password_hash
    FROM users 
    WHERE username = p_username;
    
    -- Update password
    UPDATE users 
    SET password_hash = p_new_password_hash,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_changed_by
    WHERE username = p_username;
    
    -- Log the password change
    INSERT INTO audit_log (user_id, action, entity_type, entity_id, old_values, new_values, created_at)
    VALUES (
        p_changed_by,
        'PASSWORD_CHANGE',
        'users',
        (SELECT id FROM users WHERE username = p_username),
        JSON_OBJECT('password_hash_changed', TRUE),
        JSON_OBJECT('password_hash_changed', TRUE),
        CURRENT_TIMESTAMP
    );
    
    SELECT 'Password changed successfully' AS result;
END$$

DELIMITER ;

-- ============================================
-- IMPROVED VIEWS
-- ============================================

-- Enhanced shipment summary view
CREATE VIEW shipment_summary_view AS
SELECT 
    s.id,
    s.tracking_number,
    s.status,
    c.company_name as customer_name,
    c.contact_person,
    CONCAT(s.origin_city, ', ', s.origin_state, ' → ', s.destination_city, ', ', s.destination_state) as route,
    s.estimated_delivery,
    s.total_amount,
    s.payment_status,
    DATEDIFF(s.estimated_delivery, NOW()) as days_remaining,
    CASE 
        WHEN s.status = 'delivered' AND s.actual_delivery <= s.estimated_delivery THEN 'On Time'
        WHEN s.status = 'delivered' AND s.actual_delivery > s.estimated_delivery THEN 'Late'
        WHEN s.status IN ('pending', 'pickup_scheduled') AND DATEDIFF(s.estimated_delivery, NOW()) > 3 THEN 'On Track'
        WHEN s.status IN ('in_transit', 'out_for_delivery') AND DATEDIFF(s.estimated_delivery, NOW()) >= 0 THEN 'In Progress'
        ELSE 'Needs Attention'
    END as delivery_status,
    s.created_at
FROM shipments s
JOIN customers c ON s.customer_id = c.id
WHERE s.status != 'cancelled'
ORDER BY s.created_at DESC;

-- Enhanced daily shipment statistics
CREATE VIEW daily_shipment_stats AS
SELECT 
    DATE(created_at) as shipment_date,
    COUNT(*) as total_shipments,
    SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) as delivered,
    SUM(CASE WHEN status IN ('pending', 'pickup_scheduled') THEN 1 ELSE 0 END) as pending,
    SUM(CASE WHEN status = 'in_transit' THEN 1 ELSE 0 END) as in_transit,
    SUM(CASE WHEN status IN ('delayed', 'cancelled', 'lost') THEN 1 ELSE 0 END) as issues,
    AVG(total_amount) as avg_revenue,
    SUM(total_amount) as total_revenue,
    COUNT(DISTINCT customer_id) as unique_customers
FROM shipments
GROUP BY DATE(created_at)
ORDER BY shipment_date DESC;

-- Enhanced customer activity view
CREATE VIEW customer_activity_view AS
SELECT 
    c.id,
    c.company_name,
    c.contact_person,
    c.email,
    c.customer_type,
    c.account_balance,
    c.credit_limit,
    COUNT(s.id) as total_shipments,
    SUM(CASE WHEN s.status = 'delivered' THEN 1 ELSE 0 END) as delivered_shipments,
    SUM(CASE WHEN s.status = 'delayed' THEN 1 ELSE 0 END) as delayed_shipments,
    COALESCE(SUM(s.total_amount), 0) as total_spent,
    COALESCE(AVG(s.total_amount), 0) as avg_shipment_value,
    MAX(s.created_at) as last_shipment_date,
    CASE 
        WHEN COUNT(s.id) = 0 THEN 'New'
        WHEN DATEDIFF(NOW(), MAX(s.created_at)) > 90 THEN 'Inactive'
        WHEN DATEDIFF(NOW(), MAX(s.created_at)) <= 30 THEN 'Active'
        ELSE 'Regular'
    END as customer_status
FROM customers c
LEFT JOIN shipments s ON c.id = s.customer_id
GROUP BY c.id
ORDER BY total_spent DESC;

-- Enhanced warehouse capacity view
CREATE VIEW warehouse_capacity_view AS
SELECT 
    w.id,
    w.code,
    w.name,
    w.city,
    w.state,
    w.capacity_sqft,
    w.current_utilization,
    ROUND((w.current_utilization / 100) * w.capacity_sqft, 2) as used_space,
    ROUND(w.capacity_sqft - ((w.current_utilization / 100) * w.capacity_sqft), 2) as available_space,
    CONCAT(w.current_utilization, '%') as utilization_percentage,
    COUNT(DISTINCT s.id) as active_shipments,
    GROUP_CONCAT(DISTINCT s.tracking_number ORDER BY s.created_at DESC SEPARATOR ', ') as recent_shipments,
    CASE 
        WHEN w.current_utilization >= 90 THEN 'Full'
        WHEN w.current_utilization >= 75 THEN 'High'
        WHEN w.current_utilization >= 50 THEN 'Medium'
        ELSE 'Low'
    END as capacity_status
FROM warehouses w
LEFT JOIN shipments s ON w.id = s.assigned_warehouse_id 
    AND s.status IN ('at_warehouse', 'pending', 'in_transit')
GROUP BY w.id
ORDER BY w.current_utilization DESC;

-- New view: Active shipments requiring attention
CREATE VIEW attention_required_shipments AS
SELECT 
    s.id,
    s.tracking_number,
    s.status,
    c.company_name,
    CONCAT(s.origin_city, ' → ', s.destination_city) as route,
    s.estimated_delivery,
    DATEDIFF(s.estimated_delivery, NOW()) as days_until_due,
    s.payment_status,
    s.total_amount,
    CASE 
        WHEN s.status = 'delayed' AND DATEDIFF(NOW(), s.estimated_delivery) > 7 THEN 'Critical Delay'
        WHEN s.status = 'delayed' THEN 'Delayed'
        WHEN s.payment_status = 'overdue' THEN 'Payment Overdue'
        WHEN DATEDIFF(s.estimated_delivery, NOW()) < 0 AND s.status != 'delivered' THEN 'Past Due'
        WHEN DATEDIFF(s.estimated_delivery, NOW()) <= 1 AND s.status NOT IN ('delivered', 'cancelled') THEN 'Due Tomorrow'
        ELSE 'Normal'
    END as priority,
    s.created_at
FROM shipments s
JOIN customers c ON s.customer_id = c.id
WHERE s.status NOT IN ('delivered', 'cancelled')
AND (
    s.status = 'delayed' 
    OR s.payment_status = 'overdue'
    OR DATEDIFF(s.estimated_delivery, NOW()) <= 2
)
ORDER BY 
    CASE priority
        WHEN 'Critical Delay' THEN 1
        WHEN 'Delayed' THEN 2
        WHEN 'Payment Overdue' THEN 3
        WHEN 'Past Due' THEN 4
        WHEN 'Due Tomorrow' THEN 5
        ELSE 6
    END,
    days_until_due;

-- ============================================
-- IMPROVED FUNCTIONS
-- ============================================

DELIMITER $$

-- Improved function to calculate shipment age with status consideration
CREATE FUNCTION get_shipment_age(shipment_id INT) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE age_days INT;
    DECLARE shipment_status VARCHAR(50);
    
    -- Get shipment status
    SELECT status INTO shipment_status
    FROM shipments
    WHERE id = shipment_id;
    
    IF shipment_status = 'delivered' THEN
        -- For delivered shipments, calculate from creation to delivery
        SELECT DATEDIFF(COALESCE(actual_delivery, NOW()), created_at) INTO age_days
        FROM shipments
        WHERE id = shipment_id;
    ELSE
        -- For other shipments, calculate from creation to now
        SELECT DATEDIFF(NOW(), created_at) INTO age_days
        FROM shipments
        WHERE id = shipment_id;
    END IF;
    
    RETURN COALESCE(age_days, 0);
END$$

-- Improved function to get customer status with more categories
CREATE FUNCTION get_customer_status(customer_id INT) 
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE customer_status VARCHAR(20);
    DECLARE last_shipment_date DATE;
    DECLARE total_shipments INT;
    DECLARE total_spent DECIMAL(10,2);
    DECLARE account_balance DECIMAL(10,2);
    
    -- Get customer data
    SELECT 
        MAX(s.created_at),
        COUNT(s.id),
        COALESCE(SUM(s.total_amount), 0),
        c.account_balance
    INTO 
        last_shipment_date,
        total_shipments,
        total_spent,
        account_balance
    FROM customers c
    LEFT JOIN shipments s ON c.id = s.customer_id
    WHERE c.id = customer_id;
    
    IF total_shipments = 0 THEN
        SET customer_status = 'New';
    ELSEIF account_balance < -500 THEN
        SET customer_status = 'Overdue';
    ELSEIF DATEDIFF(NOW(), last_shipment_date) > 180 THEN
        SET customer_status = 'Inactive';
    ELSEIF DATEDIFF(NOW(), last_shipment_date) > 90 THEN
        SET customer_status = 'Dormant';
    ELSEIF total_spent > 10000 THEN
        SET customer_status = 'Premium';
    ELSEIF DATEDIFF(NOW(), last_shipment_date) <= 30 THEN
        SET customer_status = 'Active';
    ELSE
        SET customer_status = 'Regular';
    END IF;
    
    RETURN customer_status;
END$$

-- Function to calculate estimated delivery date based on route and service
CREATE FUNCTION calculate_estimated_delivery(
    p_origin_city VARCHAR(50),
    p_destination_city VARCHAR(50),
    p_service_type VARCHAR(50),
    p_pickup_date DATETIME
) 
RETURNS DATETIME
DETERMINISTIC
BEGIN
    DECLARE base_days INT;
    DECLARE service_modifier DECIMAL(3,1);
    DECLARE estimated_date DATETIME;
    
    -- Base transit days (simplified logic)
    IF p_origin_city = p_destination_city THEN
        SET base_days = 1;
    ELSE
        SET base_days = 3; -- Default inter-city transit
    END IF;
    
    -- Service type modifier
    SET service_modifier = CASE p_service_type
        WHEN 'express' THEN 0.5
        WHEN 'overnight' THEN 0.3
        WHEN 'economy' THEN 1.5
        ELSE 1.0
    END;
    
    -- Calculate estimated date
    SET estimated_date = DATE_ADD(p_pickup_date, INTERVAL ROUND(base_days * service_modifier) DAY);
    
    -- Adjust for weekends
    WHILE DAYOFWEEK(estimated_date) IN (1,7) DO
        SET estimated_date = DATE_ADD(estimated_date, INTERVAL 1 DAY);
    END WHILE;
    
    RETURN estimated_date;
END$$

DELIMITER ;

-- ============================================
-- SECURE SAMPLE DATA
-- ============================================

-- Insert admin user with secure password placeholder
-- NOTE: These are development passwords. CHANGE IN PRODUCTION!
INSERT INTO users (username, email, password_hash, role, first_name, last_name, phone, is_active, created_by) 
VALUES 
('admin', 'admin@logistics.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'admin', 'System', 'Administrator', '+1234567890', TRUE, 1),
('manager1', 'manager@logistics.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'manager', 'John', 'Manager', '+1234567891', TRUE, 1),
('driver1', 'driver1@logistics.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'staff', 'Mike', 'Driver', '+1234567892', TRUE, 1),
('staff1', 'staff@logistics.com', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'staff', 'Sarah', 'Staff', '+1234567893', TRUE, 1);

-- Insert sample customers
INSERT INTO customers (company_name, contact_person, email, phone, address, city, state, country, postal_code, customer_type, is_active, credit_limit) 
VALUES 
('Tech Solutions Inc.', 'Alice Johnson', 'alice@techsolutions.com', '+1987654321', '123 Tech Street', 'San Francisco', 'CA', 'USA', '94107', 'corporate', TRUE, 50000.00),
('Global Imports Ltd.', 'Bob Smith', 'bob@globalimports.com', '+1987654322', '456 Trade Avenue', 'New York', 'NY', 'USA', '10001', 'business', TRUE, 25000.00),
('Fresh Foods Market', 'Carol Williams', 'carol@freshfoods.com', '+1987654323', '789 Food Lane', 'Chicago', 'IL', 'USA', '60601', 'business', TRUE, 15000.00),
('Quick Retail Stores', 'David Brown', 'david@quickretail.com', '+1987654324', '321 Shop Road', 'Miami', 'FL', 'USA', '33101', 'corporate', TRUE, 75000.00),
('Prime Manufacturing', 'Eva Davis', 'eva@primemfg.com', '+1987654325', '654 Factory Blvd', 'Detroit', 'MI', 'USA', '48201', 'corporate', TRUE, 100000.00);

-- Insert sample warehouses
INSERT INTO warehouses (code, name, address, city, state, country, postal_code, phone, email, capacity_sqft, current_utilization, is_active, manager_id)
VALUES 
('WH-SF-001', 'San Francisco Main Warehouse', '123 Warehouse Drive', 'San Francisco', 'CA', 'USA', '94103', '+14155551234', 'warehouse.sf@logistics.com', 75000.00, 65.50, TRUE, 2),
('WH-NYC-001', 'New York Distribution Center', '456 Distribution Ave', 'New York', 'NY', 'USA', '10002', '+12125551234', 'warehouse.nyc@logistics.com', 100000.00, 78.25, TRUE, 2),
('WH-CHI-001', 'Chicago Hub', '789 Logistics Park', 'Chicago', 'IL', 'USA', '60607', '+13125551234', 'warehouse.chi@logistics.com', 60000.00, 45.75, TRUE, 2),
('WH-MIA-001', 'Miami Storage Facility', '321 Port Road', 'Miami', 'FL', 'USA', '33132', '+13055551234', 'warehouse.mia@logistics.com', 85000.00, 32.00, TRUE, 2);

-- Insert sample vehicles
INSERT INTO vehicles (vehicle_number, vehicle_type, make, model, year, capacity_kg, current_location, status, assigned_driver_id, last_maintenance_date, next_maintenance_date, insurance_expiry, registration_expiry)
VALUES 
('TRK-001', 'Delivery Truck', 'Ford', 'F-150', 2022, 1500.00, 'San Francisco', 'available', 3, '2024-01-15', '2024-07-15', '2024-12-31', '2024-12-31'),
('VAN-001', 'Cargo Van', 'Mercedes', 'Sprinter', 2021, 2500.00, 'New York', 'in_use', NULL, '2024-02-20', '2024-08-20', '2024-11-30', '2024-11-30'),
('TRK-002', 'Refrigerated Truck', 'Freightliner', 'Cascadia', 2023, 18000.00, 'Chicago', 'available', NULL, '2024-03-10', '2024-09-10', '2025-01-31', '2025-01-31'),
('VAN-002', 'Box Truck', 'Isuzu', 'NQR', 2020, 3000.00, 'Miami', 'maintenance', NULL, '2023-12-05', '2024-06-05', '2024-10-31', '2024-10-31');

-- ============================================
-- ENHANCED EVENTS (Scheduled Tasks)
-- ============================================

DELIMITER $$

-- Event to clean old audit logs (keeps logs for 180 days)
CREATE EVENT IF NOT EXISTS clean_old_audit_logs
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP + INTERVAL 1 DAY
DO
BEGIN
    -- Keep audit logs for 180 days
    DELETE FROM audit_log WHERE created_at < DATE_SUB(NOW(), INTERVAL 180 DAY);
    
    -- Keep status history for 365 days
    DELETE FROM status_history WHERE created_at < DATE_SUB(NOW(), INTERVAL 365 DAY);
END$$

-- Enhanced event to update shipment statuses
CREATE EVENT IF NOT EXISTS update_overdue_shipments
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Mark shipments as delayed if past estimated delivery
    UPDATE shipments 
    SET status = 'delayed',
        updated_at = CURRENT_TIMESTAMP
    WHERE status IN ('out_for_delivery', 'in_transit', 'pending', 'pickup_scheduled')
    AND estimated_delivery < NOW()
    AND actual_delivery IS NULL
    AND status != 'delayed';
    
    -- Mark invoices as overdue if past due date
    UPDATE invoices
    SET status = 'overdue',
        updated_at = CURRENT_TIMESTAMP
    WHERE status = 'sent'
    AND due_date < CURDATE();
END$$

-- Event to update warehouse utilization
CREATE EVENT IF NOT EXISTS update_warehouse_utilization
ON SCHEDULE EVERY 6 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE warehouses w
    LEFT JOIN (
        SELECT assigned_warehouse_id, COUNT(*) as active_shipments
        FROM shipments
        WHERE status IN ('at_warehouse')
        GROUP BY assigned_warehouse_id
    ) s ON w.id = s.assigned_warehouse_id
    SET w.current_utilization = 
        CASE 
            WHEN s.active_shipments IS NULL THEN 0
            ELSE LEAST(100, (s.active_shipments * 100) / (w.capacity_sqft / 1000))
        END,
        w.updated_at = CURRENT_TIMESTAMP;
END$$

-- Event to generate daily statistics
CREATE EVENT IF NOT EXISTS generate_daily_statistics
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 23:59:59'
DO
BEGIN
    -- Create statistics cache table if not exists
    CREATE TABLE IF NOT EXISTS daily_shipment_stats_cache (
        id INT PRIMARY KEY AUTO_INCREMENT,
        stat_date DATE NOT NULL,
        total_shipments INT DEFAULT 0,
        delivered INT DEFAULT 0,
        pending INT DEFAULT 0,
        in_transit INT DEFAULT 0,
        delayed INT DEFAULT 0,
        revenue DECIMAL(10,2) DEFAULT 0.00,
        unique_customers INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY idx_stat_date (stat_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    
    -- Insert statistics for previous day
    INSERT INTO daily_shipment_stats_cache 
        (stat_date, total_shipments, delivered, pending, in_transit, delayed, revenue, unique_customers)
    SELECT 
        CURDATE() - INTERVAL 1 DAY,
        COUNT(*),
        SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status IN ('pending', 'pickup_scheduled') THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'in_transit' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'delayed' THEN 1 ELSE 0 END),
        COALESCE(SUM(CASE WHEN status = 'delivered' THEN total_amount ELSE 0 END), 0),
        COUNT(DISTINCT customer_id)
    FROM shipments
    WHERE DATE(created_at) = CURDATE() - INTERVAL 1 DAY
    ON DUPLICATE KEY UPDATE
        total_shipments = VALUES(total_shipments),
        delivered = VALUES(delivered),
        pending = VALUES(pending),
        in_transit = VALUES(in_transit),
        delayed = VALUES(delayed),
        revenue = VALUES(revenue),
        unique_customers = VALUES(unique_customers),
        created_at = CURRENT_TIMESTAMP;
END$$

DELIMITER ;

-- Enable the event scheduler
SET GLOBAL event_scheduler = ON;

-- ============================================
-- GRANT PERMISSIONS (Improved Security)
-- ============================================

-- Create application user with specific privileges
CREATE USER IF NOT EXISTS 'logistics_app'@'localhost' IDENTIFIED BY 'SecureAppPassword123!';
CREATE USER IF NOT EXISTS 'logistics_app'@'%' IDENTIFIED BY 'SecureAppPassword123!';

-- Grant specific privileges (principle of least privilege)
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.users TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.customers TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.shipments TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT ON logistics_platform.status_history TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.warehouses TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.vehicles TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.invoices TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON logistics_platform.invoice_items TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT, UPDATE ON logistics_platform.payments TO 'logistics_app'@'localhost';
GRANT SELECT, INSERT ON logistics_platform.audit_log TO 'logistics_app'@'localhost';

-- Grant read-only access to views
GRANT SELECT ON logistics_platform.shipment_summary_view TO 'logistics_app'@'localhost';
GRANT SELECT ON logistics_platform.daily_shipment_stats TO 'logistics_app'@'localhost';
GRANT SELECT ON logistics_platform.customer_activity_view TO 'logistics_app'@'localhost';
GRANT SELECT ON logistics_platform.warehouse_capacity_view TO 'logistics_app'@'localhost';
GRANT SELECT ON logistics_platform.attention_required_shipments TO 'logistics_app'@'localhost';

-- Grant execute on procedures
GRANT EXECUTE ON PROCEDURE logistics_platform.generate_tracking_number TO 'logistics_app'@'localhost';
GRANT EXECUTE ON PROCEDURE logistics_platform.get_shipment_statistics TO 'logistics_app'@'localhost';
GRANT EXECUTE ON PROCEDURE logistics_platform.change_user_password TO 'logistics_app'@'localhost';

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION logistics_platform.get_shipment_age TO 'logistics_app'@'localhost';
GRANT EXECUTE ON FUNCTION logistics_platform.get_customer_status TO 'logistics_app'@'localhost';
GRANT EXECUTE ON FUNCTION logistics_platform.calculate_estimated_delivery TO 'logistics_app'@'localhost';

-- Backup user (read-only access)
CREATE USER IF NOT EXISTS 'logistics_backup'@'localhost' IDENTIFIED BY 'BackupPassword456!';
GRANT SELECT, LOCK TABLES, RELOAD, PROCESS ON logistics_platform.* TO 'logistics_backup'@'localhost';

-- Read-only user for reports
CREATE USER IF NOT EXISTS 'logistics_report'@'localhost' IDENTIFIED BY 'ReportPassword789!';
GRANT SELECT ON logistics_platform.* TO 'logistics_report'@'localhost';
GRANT SELECT ON logistics_platform.shipment_summary_view TO 'logistics_report'@'localhost';
GRANT SELECT ON logistics_platform.daily_shipment_stats TO 'logistics_report'@'localhost';
GRANT SELECT ON logistics_platform.customer_activity_view TO 'logistics_report'@'localhost';

FLUSH PRIVILEGES;

-- ============================================
-- ADDITIONAL INDEXES FOR PERFORMANCE
-- ============================================

-- Composite indexes for common query patterns
CREATE INDEX idx_shipments_origin_dest_status_date ON shipments(origin_city, destination_city, status, estimated_delivery);
CREATE INDEX idx_shipments_customer_status_date ON shipments(customer_id, status, created_at DESC);
CREATE INDEX idx_status_history_status_date ON status_history(status, created_at DESC);
CREATE INDEX idx_customers_company_type_active ON customers(company_name, customer_type, is_active);
CREATE INDEX idx_invoices_customer_status_amount ON invoices(customer_id, status, total_amount DESC);
CREATE INDEX idx_payments_customer_date_status ON payments(customer_id, payment_date DESC, status);

-- Full-text indexes for search functionality
CREATE FULLTEXT INDEX idx_shipments_contents ON shipments(contents_description);
CREATE FULLTEXT INDEX idx_customers_notes ON customers(notes);
CREATE FULLTEXT INDEX idx_invoices_notes ON invoices(notes);

-- Analyze tables for optimal performance
ANALYZE TABLE users;
ANALYZE TABLE customers;
ANALYZE TABLE shipments;
ANALYZE TABLE status_history;
ANALYZE TABLE warehouses;
ANALYZE TABLE vehicles;
ANALYZE TABLE invoices;
ANALYZE TABLE invoice_items;
ANALYZE TABLE payments;
ANALYZE TABLE audit_log;

-- ============================================
-- FINALIZATION AND VERIFICATION
-- ============================================

-- Create table to track database changes
CREATE TABLE IF NOT EXISTS database_changes (
    id INT PRIMARY KEY AUTO_INCREMENT,
    version VARCHAR(20) NOT NULL,
    change_type ENUM('CREATE', 'ALTER', 'DROP', 'UPDATE') NOT NULL,
    description TEXT NOT NULL,
    script_name VARCHAR(255),
    applied_by VARCHAR(100) DEFAULT 'system',
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_version (version),
    INDEX idx_applied_at (applied_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Log this initialization
INSERT INTO database_changes (version, change_type, description, script_name, applied_by)
VALUES ('2.0', 'CREATE', 'Initial database creation with enhanced features', 'init.sql', 'system');

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

SELECT '============================================' as '';
SELECT 'LOGGISTICS PLATFORM DATABASE INITIALIZATION' as '';
SELECT '============================================' as '';
SELECT '' as '';
SELECT '✅ Database Created: logistics_platform' as '';
SELECT '✅ Tables Created: 10 tables' as '';
SELECT '✅ Views Created: 5 views' as '';
SELECT '✅ Procedures Created: 4 stored procedures' as '';
SELECT '✅ Functions Created: 3 functions' as '';
SELECT '✅ Triggers Created: 4 triggers' as '';
SELECT '✅ Events Created: 4 scheduled events' as '';
SELECT '✅ Users Created: 4 application users with specific privileges' as '';
SELECT '✅ Indexes Created: Optimized for performance' as '';
SELECT '✅ Constraints Added: Data validation and integrity' as '';
SELECT '' as '';
SELECT '📊 Sample Data Summary:' as '';
SELECT CONCAT('  • Users: ', COUNT(*)) FROM users;
SELECT CONCAT('  • Customers: ', COUNT(*)) FROM customers;
SELECT CONCAT('  • Warehouses: ', COUNT(*)) FROM warehouses;
SELECT CONCAT('  • Vehicles: ', COUNT(*)) FROM vehicles;
SELECT '' as '';
SELECT '🔐 SECURITY WARNING:' as '';
SELECT '  Default passwords are set for development only!' as '';
SELECT '  You MUST change all passwords in production:' as '';
SELECT '' as '';
SELECT '  1. Database user passwords:' as '';
SELECT '     logistics_app / SecureAppPassword123!' as '';
SELECT '     logistics_backup / BackupPassword456!' as '';
SELECT '     logistics_report / ReportPassword789!' as '';
SELECT '' as '';
SELECT '  2. Application user passwords:' as '';
SELECT '     admin / admin123' as '';
SELECT '     manager1 / admin123' as '';
SELECT '     driver1 / admin123' as '';
SELECT '     staff1 / admin123' as '';
SELECT '' as '';
SELECT '  3. Use change_user_password() procedure to update user passwords' as '';
SELECT '' as '';
SELECT '🚀 Initialization Completed Successfully!' as '';
SELECT '============================================' as '';

COMMIT;