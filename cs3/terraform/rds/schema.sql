-- CS3 Employee Management Database Schema
-- Initializes the employees table for onboarding/offboarding management

CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    department VARCHAR(255),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    role VARCHAR(50) NOT NULL DEFAULT 'employee',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    offboarded_at TIMESTAMP
);

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_email ON employees(email);
CREATE INDEX IF NOT EXISTS idx_status ON employees(status);
CREATE INDEX IF NOT EXISTS idx_department ON employees(department);

-- Employee audit log for tracking lifecycle changes
CREATE TABLE IF NOT EXISTS employee_audit_log (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,
    old_status VARCHAR(50),
    new_status VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(255)
);

-- Index for audit queries
CREATE INDEX IF NOT EXISTS idx_employee_audit ON employee_audit_log(employee_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON employee_audit_log(timestamp);

-- Employee requests for self-service portal
CREATE TABLE IF NOT EXISTS employee_requests (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL REFERENCES employees(email) ON DELETE CASCADE,
    request_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    resolved_by VARCHAR(255)
);

-- Index for request queries
CREATE INDEX IF NOT EXISTS idx_request_email ON employee_requests(email);
CREATE INDEX IF NOT EXISTS idx_request_status ON employee_requests(status);
CREATE INDEX IF NOT EXISTS idx_request_created ON employee_requests(created_at);

-- Sample data for initial testing
INSERT INTO employees (email, name, department, status, role)
VALUES 
    ('admin@innovatech.local', 'System Admin', 'IT', 'active', 'admin'),
    ('hr@innovatech.local', 'HR Manager', 'HR', 'active', 'hr'),
    ('john.doe@innovatech.local', 'John Doe', 'Engineering', 'pending', 'employee'),
    ('jane.smith@innovatech.local', 'Jane Smith', 'Operations', 'active', 'employee')
ON CONFLICT (email) DO NOTHING;
