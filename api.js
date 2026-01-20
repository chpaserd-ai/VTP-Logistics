/**
 * Logistics Platform - API Communication Module
 * Handles all API requests and responses
 */

class API {
    constructor() {
        this.baseURL = 'http://localhost:3000/api'; // Update with your backend URL
        this.authToken = null;
        this.defaultHeaders = {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        };
    }

    setAuthToken(token) {
        this.authToken = token;
    }

    clearAuthToken() {
        this.authToken = null;
    }

    async request(endpoint, options = {}) {
        const url = `${this.baseURL}${endpoint}`;
        
        // Merge headers
        const headers = {
            ...this.defaultHeaders,
            ...options.headers
        };

        // Add authorization header if token exists
        if (this.authToken && !options.skipAuth) {
            headers['Authorization'] = `Bearer ${this.authToken}`;
        }

        const config = {
            ...options,
            headers
        };

        try {
            const response = await fetch(url, config);
            
            // Handle HTTP errors
            if (!response.ok) {
                await this.handleError(response);
            }

            // Parse response based on content type
            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                return await response.json();
            } else {
                return await response.text();
            }
        } catch (error) {
            console.error(`API request failed: ${endpoint}`, error);
            throw error;
        }
    }

    async handleError(response) {
        const errorText = await response.text();
        let errorMessage = `HTTP ${response.status}: ${response.statusText}`;

        try {
            const errorData = JSON.parse(errorText);
            errorMessage = errorData.message || errorMessage;
            
            // Handle specific status codes
            switch (response.status) {
                case 401:
                    // Unauthorized - trigger logout
                    if (window.auth) {
                        window.auth.handleUnauthorized();
                    }
                    break;
                case 403:
                    // Forbidden - show access denied
                    utils.showNotification('Access denied', 'error');
                    break;
                case 404:
                    // Not found
                    errorMessage = 'Resource not found';
                    break;
                case 422:
                    // Validation error
                    if (errorData.errors) {
                        errorMessage = this.formatValidationErrors(errorData.errors);
                    }
                    break;
                case 500:
                    // Server error
                    errorMessage = 'Server error occurred';
                    break;
            }
        } catch (e) {
            // Response is not JSON
            console.error('Error parsing error response:', e);
        }

        throw new Error(errorMessage);
    }

    formatValidationErrors(errors) {
        return Object.entries(errors)
            .map(([field, messages]) => `${field}: ${messages.join(', ')}`)
            .join('\n');
    }

    // CRUD Operations
    async get(endpoint, params = {}) {
        // Build query string if params exist
        const queryString = Object.keys(params).length > 0
            ? `?${new URLSearchParams(params).toString()}`
            : '';
        
        return this.request(`${endpoint}${queryString}`, {
            method: 'GET'
        });
    }

    async post(endpoint, data = {}) {
        return this.request(endpoint, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    }

    async put(endpoint, data = {}) {
        return this.request(endpoint, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
    }

    async patch(endpoint, data = {}) {
        return this.request(endpoint, {
            method: 'PATCH',
            body: JSON.stringify(data)
        });
    }

    async delete(endpoint) {
        return this.request(endpoint, {
            method: 'DELETE'
        });
    }

    // Shipment API Methods
    async createShipment(shipmentData) {
        return this.post('/shipments', shipmentData);
    }

    async getShipments(params = {}) {
        return this.get('/shipments', params);
    }

    async getShipmentById(id) {
        return this.get(`/shipments/${id}`);
    }

    async updateShipment(id, updateData) {
        return this.put(`/shipments/${id}`, updateData);
    }

    async deleteShipment(id) {
        return this.delete(`/shipments/${id}`);
    }

    async trackShipment(trackingNumber) {
        return this.get(`/shipments/track/${trackingNumber}`);
    }

    async updateShipmentStatus(id, statusData) {
        return this.post(`/shipments/${id}/status`, statusData);
    }

    // Customer API Methods
    async createCustomer(customerData) {
        return this.post('/customers', customerData);
    }

    async getCustomers(params = {}) {
        return this.get('/customers', params);
    }

    async getCustomerById(id) {
        return this.get(`/customers/${id}`);
    }

    async updateCustomer(id, updateData) {
        return this.put(`/customers/${id}`, updateData);
    }

    async deleteCustomer(id) {
        return this.delete(`/customers/${id}`);
    }

    // Reports API Methods
    async getShipmentReport(params = {}) {
        return this.get('/reports/shipments', params);
    }

    async getCustomerReport(params = {}) {
        return this.get('/reports/customers', params);
    }

    async getRevenueReport(params = {}) {
        return this.get('/reports/revenue', params);
    }

    async getDashboardStats() {
        return this.get('/reports/dashboard-stats');
    }

    // File Upload Method
    async uploadFile(endpoint, file, onProgress = null) {
        const formData = new FormData();
        formData.append('file', file);

        return this.request(endpoint, {
            method: 'POST',
            headers: {
                // Remove Content-Type for FormData (browser will set it)
            },
            body: formData,
            onUploadProgress: onProgress
        });
    }

    // Search Method
    async search(query, type = null) {
        const params = { q: query };
        if (type) params.type = type;
        
        return this.get('/search', params);
    }

    // Export Data Method
    async exportData(type, params = {}) {
        const response = await this.request(`/export/${type}`, {
            method: 'POST',
            body: JSON.stringify(params)
        });

        // Create download link for exported file
        if (response.fileUrl) {
            const link = document.createElement('a');
            link.href = response.fileUrl;
            link.download = response.filename || `export-${type}-${Date.now()}.csv`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

        return response;
    }

    // Batch Operations
    async batchUpdateShipments(ids, updateData) {
        return this.post('/shipments/batch-update', {
            ids,
            updateData
        });
    }

    async bulkImportShipments(file) {
        return this.uploadFile('/shipments/bulk-import', file);
    }

    // Real-time Updates (WebSocket setup)
    setupWebSocket() {
        if (!this.authToken) return null;

        const wsUrl = `ws://localhost:3000/ws?token=${this.authToken}`;
        const socket = new WebSocket(wsUrl);

        socket.onopen = () => {
            console.log('WebSocket connected');
        };

        socket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };

        socket.onclose = () => {
            console.log('WebSocket disconnected');
            // Attempt to reconnect after delay
            setTimeout(() => this.setupWebSocket(), 5000);
        };

        return socket;
    }

    handleWebSocketMessage(data) {
        switch (data.type) {
            case 'SHIPMENT_UPDATED':
                this.emitEvent('shipmentUpdated', data.payload);
                break;
            case 'NEW_SHIPMENT':
                this.emitEvent('newShipment', data.payload);
                break;
            case 'STATUS_CHANGED':
                this.emitEvent('statusChanged', data.payload);
                break;
            // Add more event types as needed
        }
    }

    emitEvent(eventName, data) {
        const event = new CustomEvent(eventName, { detail: data });
        window.dispatchEvent(event);
    }
}

// Initialize API instance
const api = new API();

// Export for use in other modules
if (typeof module !== 'undefined') {
    module.exports = API;
}