/**
 * Logistics Platform - Utility Functions
 * Common helper functions used throughout the application
 */

class Utils {
    constructor() {
        // Initialize any utility configurations
    }

    // DOM Manipulation Utilities
    createElement(tag, attributes = {}, children = []) {
        const element = document.createElement(tag);
        
        // Set attributes
        Object.entries(attributes).forEach(([key, value]) => {
            if (key === 'className') {
                element.className = value;
            } else if (key === 'textContent') {
                element.textContent = value;
            } else if (key === 'html') {
                element.innerHTML = value;
            } else {
                element.setAttribute(key, value);
            }
        });
        
        // Append children
        if (Array.isArray(children)) {
            children.forEach(child => {
                if (child instanceof Node) {
                    element.appendChild(child);
                } else if (typeof child === 'string') {
                    element.appendChild(document.createTextNode(child));
                }
            });
        }
        
        return element;
    }

    query(selector, parent = document) {
        return parent.querySelector(selector);
    }

    queryAll(selector, parent = document) {
        return Array.from(parent.querySelectorAll(selector));
    }

    removeElement(selector) {
        const element = this.query(selector);
        if (element) {
            element.remove();
        }
    }

    toggleClass(element, className) {
        if (element) {
            element.classList.toggle(className);
        }
    }

    // Form Handling
    serializeForm(form) {
        const formData = new FormData(form);
        const data = {};
        
        for (const [key, value] of formData.entries()) {
            if (data[key]) {
                if (!Array.isArray(data[key])) {
                    data[key] = [data[key]];
                }
                data[key].push(value);
            } else {
                data[key] = value;
            }
        }
        
        return data;
    }

    validateForm(form, validationRules) {
        const errors = {};
        const formData = this.serializeForm(form);
        
        Object.entries(validationRules).forEach(([field, rules]) => {
            const value = formData[field];
            
            rules.forEach(rule => {
                if (!this.validateRule(value, rule)) {
                    if (!errors[field]) {
                        errors[field] = [];
                    }
                    errors[field].push(rule.message);
                }
            });
        });
        
        return {
            isValid: Object.keys(errors).length === 0,
            errors
        };
    }

    validateRule(value, rule) {
        switch (rule.type) {
            case 'required':
                return value !== undefined && value !== null && value !== '';
            case 'email':
                return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
            case 'minLength':
                return value.length >= rule.value;
            case 'maxLength':
                return value.length <= rule.value;
            case 'pattern':
                return rule.pattern.test(value);
            case 'custom':
                return rule.validate(value);
            default:
                return true;
        }
    }

    // Date and Time Utilities
    formatDate(date, format = 'medium') {
        if (!date) return 'N/A';
        
        const d = new Date(date);
        
        if (isNaN(d.getTime())) return 'Invalid Date';
        
        const formats = {
            short: {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            },
            medium: {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            },
            long: {
                year: 'numeric',
                month: 'long',
                day: 'numeric',
                weekday: 'long'
            },
            time: {
                hour: '2-digit',
                minute: '2-digit'
            }
        };
        
        return d.toLocaleDateString('en-US', formats[format] || formats.medium);
    }

    formatDateTime(date) {
        if (!date) return 'N/A';
        
        const d = new Date(date);
        if (isNaN(d.getTime())) return 'Invalid Date';
        
        return `${this.formatDate(d, 'short')} ${d.toLocaleTimeString([], { 
            hour: '2-digit', 
            minute: '2-digit' 
        })}`;
    }

    timeAgo(date) {
        const now = new Date();
        const past = new Date(date);
        const diffInSeconds = Math.floor((now - past) / 1000);
        
        const intervals = {
            year: 31536000,
            month: 2592000,
            week: 604800,
            day: 86400,
            hour: 3600,
            minute: 60,
            second: 1
        };
        
        for (const [unit, seconds] of Object.entries(intervals)) {
            const interval = Math.floor(diffInSeconds / seconds);
            if (interval >= 1) {
                return interval === 1 ? `1 ${unit} ago` : `${interval} ${unit}s ago`;
            }
        }
        
        return 'just now';
    }

    // Notification System
    showNotification(message, type = 'info', duration = 5000) {
        // Remove existing notifications
        const existing = document.querySelector('.notification');
        if (existing) {
            existing.remove();
        }
        
        const notification = this.createElement('div', {
            className: `notification notification-${type}`,
            html: `
                <div class="notification-content">
                    <span class="notification-icon">${this.getNotificationIcon(type)}</span>
                    <span class="notification-message">${message}</span>
                </div>
                <button class="notification-close">&times;</button>
            `
        });
        
        document.body.appendChild(notification);
        
        // Add close functionality
        const closeBtn = notification.querySelector('.notification-close');
        closeBtn.addEventListener('click', () => {
            notification.remove();
        });
        
        // Auto-remove after duration
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, duration);
        
        return notification;
    }

    getNotificationIcon(type) {
        const icons = {
            success: '✓',
            error: '✗',
            warning: '⚠',
            info: 'ℹ'
        };
        return icons[type] || icons.info;
    }

    // Modal System
    showModal(modalId, options = {}) {
        // Close any existing modal
        this.closeModal();
        
        // Create modal overlay
        const overlay = this.createElement('div', {
            className: 'modal-overlay'
        });
        
        // Create modal container
        const modal = this.createElement('div', {
            className: 'modal',
            id: modalId
        });
        
        // Add modal content
        const content = this.createElement('div', {
            className: 'modal-content',
            html: `
                <div class="modal-header">
                    <h3>${options.title || 'Modal'}</h3>
                    <button class="modal-close">&times;</button>
                </div>
                <div class="modal-body">
                    ${options.content || ''}
                </div>
                ${options.footer ? `
                <div class="modal-footer">
                    ${options.footer}
                </div>
                ` : ''}
            `
        });
        
        modal.appendChild(content);
        overlay.appendChild(modal);
        document.body.appendChild(overlay);
        
        // Add close functionality
        const closeBtn = modal.querySelector('.modal-close');
        closeBtn.addEventListener('click', () => this.closeModal());
        
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                this.closeModal();
            }
        });
        
        // Escape key to close
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.closeModal();
            }
        });
        
        // Focus first input if present
        setTimeout(() => {
            const firstInput = modal.querySelector('input, select, textarea');
            if (firstInput) {
                firstInput.focus();
            }
        }, 100);
        
        return modal;
    }

    closeModal() {
        const overlay = document.querySelector('.modal-overlay');
        if (overlay) {
            overlay.remove();
        }
    }

    // Loading State Management
    showLoading(selector = 'body') {
        const container = this.query(selector);
        if (container) {
            const loading = this.createElement('div', {
                className: 'loading-overlay',
                html: '<div class="loading-spinner"></div>'
            });
            container.appendChild(loading);
        }
    }

    hideLoading() {
        const loading = document.querySelector('.loading-overlay');
        if (loading) {
            loading.remove();
        }
    }

    // Data Formatting
    formatCurrency(amount, currency = 'USD') {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: currency
        }).format(amount);
    }

    formatNumber(number) {
        return new Intl.NumberFormat('en-US').format(number);
    }

    formatWeight(weight, unit = 'kg') {
        return `${this.formatNumber(weight)} ${unit}`;
    }

    // Storage Utilities
    setStorage(key, value, isSession = false) {
        const storage = isSession ? sessionStorage : localStorage;
        storage.setItem(key, JSON.stringify(value));
    }

    getStorage(key, isSession = false) {
        const storage = isSession ? sessionStorage : localStorage;
        const value = storage.getItem(key);
        try {
            return value ? JSON.parse(value) : null;
        } catch {
            return value;
        }
    }

    removeStorage(key, isSession = false) {
        const storage = isSession ? sessionStorage : localStorage;
        storage.removeItem(key);
    }

    // String Utilities
    truncate(text, length = 100) {
        if (text.length <= length) return text;
        return text.substring(0, length) + '...';
    }

    capitalize(text) {
        return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
    }

    generateId(length = 8) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        let result = '';
        for (let i = 0; i < length; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return result;
    }

    // Validation Utilities
    isValidEmail(email) {
        const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return regex.test(email);
    }

    isValidPhone(phone) {
        const regex = /^[\+]?[1-9][\d]{0,15}$/;
        return regex.test(phone.replace(/[\s\-\(\)]/g, ''));
    }

    isValidTrackingNumber(trackingNumber) {
        // Basic validation - adjust based on your tracking number format
        const regex = /^[A-Z0-9]{8,20}$/;
        return regex.test(trackingNumber);
    }

    // Debounce and Throttle
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    throttle(func, limit) {
        let inThrottle;
        return function executedFunction(...args) {
            if (!inThrottle) {
                func(...args);
                inThrottle = true;
                setTimeout(() => inThrottle = false, limit);
            }
        };
    }

    // File Utilities
    readFileAsText(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => resolve(e.target.result);
            reader.onerror = (e) => reject(e);
            reader.readAsText(file);
        });
    }

    downloadFile(content, filename, type = 'text/plain') {
        const blob = new Blob([content], { type });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    // Performance Monitoring
    measurePerformance(name, func) {
        const start = performance.now();
        const result = func();
        const end = performance.now();
        console.log(`${name} took ${end - start}ms`);
        return result;
    }
}

// Initialize utilities
const utils = new Utils();

// Export for use in other modules
if (typeof module !== 'undefined') {
    module.exports = Utils;
}