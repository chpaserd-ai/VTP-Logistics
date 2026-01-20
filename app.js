/**
 * Logistics Platform - Main Application Logic
 * Handles UI interactions and page-specific functionality
 */

class LogisticsApp {
    constructor() {
        this.currentUser = null;
        this.init();
    }

    init() {
        // Check authentication status
        this.checkAuth();
        
        // Initialize event listeners
        this.initEventListeners();
        
        // Load initial data if authenticated
        if (this.currentUser) {
            this.loadDashboardData();
        }
    }

    checkAuth() {
        const token = localStorage.getItem('authToken');
        const user = localStorage.getItem('user');
        
        if (token && user) {
            this.currentUser = JSON.parse(user);
            this.updateUIForLoggedInUser();
        } else {
            this.redirectToLogin();
        }
    }

    updateUIForLoggedInUser() {
        // Update navigation based on user role
        const userRole = this.currentUser?.role;
        const navItems = document.querySelectorAll('.nav-item');
        
        navItems.forEach(item => {
            const requiredRole = item.dataset.role;
            if (requiredRole && requiredRole !== userRole) {
                item.style.display = 'none';
            }
        });

        // Update user info in UI
        const userInfoElements = document.querySelectorAll('.user-info');
        userInfoElements.forEach(el => {
            if (el.id === 'user-name') {
                el.textContent = this.currentUser.name;
            } else if (el.id === 'user-email') {
                el.textContent = this.currentUser.email;
            }
        });
    }

    async loadDashboardData() {
        try {
            // Load recent shipments
            const shipments = await api.get('/shipments/recent');
            this.renderRecentShipments(shipments);

            // Load statistics
            const stats = await api.get('/reports/dashboard-stats');
            this.renderDashboardStats(stats);

            // Load pending tasks
            const tasks = await api.get('/shipments/pending');
            this.renderPendingTasks(tasks);
        } catch (error) {
            console.error('Error loading dashboard data:', error);
            utils.showNotification('Failed to load dashboard data', 'error');
        }
    }

    renderRecentShipments(shipments) {
        const container = document.getElementById('recent-shipments');
        if (!container) return;

        if (shipments.length === 0) {
            container.innerHTML = '<p class="empty-state">No recent shipments found.</p>';
            return;
        }

        const html = shipments.map(shipment => `
            <div class="shipment-card">
                <div class="shipment-header">
                    <span class="tracking-number">${shipment.trackingNumber}</span>
                    <span class="status-badge status-${shipment.status.toLowerCase()}">
                        ${shipment.status}
                    </span>
                </div>
                <div class="shipment-details">
                    <div class="route">
                        <span class="origin">${shipment.origin}</span>
                        <span class="arrow">→</span>
                        <span class="destination">${shipment.destination}</span>
                    </div>
                    <div class="meta">
                        <span class="date">${utils.formatDate(shipment.estimatedDelivery)}</span>
                        <span class="weight">${shipment.weight} kg</span>
                    </div>
                </div>
                <div class="shipment-actions">
                    <button class="btn btn-sm btn-outline" onclick="app.viewShipment('${shipment._id}')">
                        View Details
                    </button>
                </div>
            </div>
        `).join('');

        container.innerHTML = html;
    }

    renderDashboardStats(stats) {
        const statsContainer = document.getElementById('dashboard-stats');
        if (!statsContainer) return;

        statsContainer.innerHTML = `
            <div class="stat-card">
                <div class="stat-icon">
                    <i class="fas fa-shipping-fast"></i>
                </div>
                <div class="stat-info">
                    <h3>${stats.totalShipments}</h3>
                    <p>Total Shipments</p>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon">
                    <i class="fas fa-clock"></i>
                </div>
                <div class="stat-info">
                    <h3>${stats.pendingShipments}</h3>
                    <p>Pending</p>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon">
                    <i class="fas fa-check-circle"></i>
                </div>
                <div class="stat-info">
                    <h3>${stats.deliveredShipments}</h3>
                    <p>Delivered</p>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon">
                    <i class="fas fa-users"></i>
                </div>
                <div class="stat-info">
                    <h3>${stats.totalCustomers}</h3>
                    <p>Customers</p>
                </div>
            </div>
        `;
    }

    renderPendingTasks(tasks) {
        const container = document.getElementById('pending-tasks');
        if (!container) return;

        if (tasks.length === 0) {
            container.innerHTML = '<p class="empty-state">No pending tasks.</p>';
            return;
        }

        const html = tasks.map(task => `
            <div class="task-item">
                <div class="task-info">
                    <h4>${task.type}</h4>
                    <p>${task.description}</p>
                    <small>Due: ${utils.formatDate(task.dueDate)}</small>
                </div>
                <div class="task-actions">
                    <button class="btn btn-sm" onclick="app.completeTask('${task._id}')">
                        Complete
                    </button>
                </div>
            </div>
        `).join('');

        container.innerHTML = html;
    }

    async viewShipment(shipmentId) {
        try {
            const shipment = await api.get(`/shipments/${shipmentId}`);
            this.openShipmentModal(shipment);
        } catch (error) {
            console.error('Error loading shipment:', error);
            utils.showNotification('Failed to load shipment details', 'error');
        }
    }

    openShipmentModal(shipment) {
        // Implementation for shipment modal
        utils.showModal('shipment-details-modal', {
            title: `Shipment: ${shipment.trackingNumber}`,
            content: this.generateShipmentDetailsHTML(shipment)
        });
    }

    generateShipmentDetailsHTML(shipment) {
        return `
            <div class="shipment-details-modal">
                <div class="detail-section">
                    <h4>Basic Information</h4>
                    <div class="detail-grid">
                        <div class="detail-item">
                            <label>Tracking Number:</label>
                            <span>${shipment.trackingNumber}</span>
                        </div>
                        <div class="detail-item">
                            <label>Status:</label>
                            <span class="status-badge status-${shipment.status.toLowerCase()}">
                                ${shipment.status}
                            </span>
                        </div>
                        <div class="detail-item">
                            <label>Estimated Delivery:</label>
                            <span>${utils.formatDate(shipment.estimatedDelivery)}</span>
                        </div>
                    </div>
                </div>
                
                <div class="detail-section">
                    <h4>Route Information</h4>
                    <div class="route-display">
                        <div class="route-point origin">
                            <strong>Origin:</strong> ${shipment.origin}
                        </div>
                        <div class="route-line"></div>
                        <div class="route-point destination">
                            <strong>Destination:</strong> ${shipment.destination}
                        </div>
                    </div>
                </div>
                
                <div class="detail-section">
                    <h4>Status History</h4>
                    <div class="timeline">
                        ${shipment.statusHistory?.map(history => `
                            <div class="timeline-item">
                                <div class="timeline-marker"></div>
                                <div class="timeline-content">
                                    <h5>${history.status}</h5>
                                    <p>${history.description}</p>
                                    <small>${utils.formatDateTime(history.timestamp)}</small>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                </div>
            </div>
        `;
    }

    async completeTask(taskId) {
        try {
            await api.put(`/tasks/${taskId}/complete`);
            utils.showNotification('Task completed successfully', 'success');
            this.loadDashboardData();
        } catch (error) {
            console.error('Error completing task:', error);
            utils.showNotification('Failed to complete task', 'error');
        }
    }

    initEventListeners() {
        // Logout button
        const logoutBtn = document.getElementById('logout-btn');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', () => this.logout());
        }

        // Navigation menu
        const navLinks = document.querySelectorAll('.nav-link');
        navLinks.forEach(link => {
            link.addEventListener('click', (e) => this.handleNavigation(e));
        });

        // Search functionality
        const searchInput = document.getElementById('search-input');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => this.handleSearch(e));
        }

        // Modal close buttons
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('modal-close') || 
                e.target.classList.contains('modal-overlay')) {
                utils.closeModal();
            }
        });

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.key === 'k') {
                e.preventDefault();
                document.getElementById('search-input')?.focus();
            }
            if (e.key === 'Escape') {
                utils.closeModal();
            }
        });
    }

    handleNavigation(e) {
        e.preventDefault();
        const target = e.target.closest('a');
        if (!target) return;

        const page = target.getAttribute('href');
        this.navigateTo(page);
    }

    navigateTo(page) {
        window.location.href = page;
    }

    async handleSearch(e) {
        const query = e.target.value.trim();
        if (query.length < 2) return;

        try {
            const results = await api.get(`/search?q=${encodeURIComponent(query)}`);
            this.displaySearchResults(results);
        } catch (error) {
            console.error('Search error:', error);
        }
    }

    displaySearchResults(results) {
        // Implementation for search results dropdown
        const container = document.getElementById('search-results');
        if (!container) return;

        if (results.length === 0) {
            container.innerHTML = '<div class="search-result-item">No results found</div>';
            container.classList.add('active');
            return;
        }

        const html = results.map(result => `
            <div class="search-result-item" onclick="app.handleSearchResultClick('${result.type}', '${result.id}')">
                <div class="result-type">${result.type}</div>
                <div class="result-title">${result.title}</div>
                ${result.subtitle ? `<div class="result-subtitle">${result.subtitle}</div>` : ''}
            </div>
        `).join('');

        container.innerHTML = html;
        container.classList.add('active');
    }

    handleSearchResultClick(type, id) {
        switch (type) {
            case 'shipment':
                this.viewShipment(id);
                break;
            case 'customer':
                this.viewCustomer(id);
                break;
            // Add more cases as needed
        }
        
        // Clear search
        document.getElementById('search-input').value = '';
        document.getElementById('search-results').classList.remove('active');
    }

    async viewCustomer(customerId) {
        try {
            const customer = await api.get(`/customers/${customerId}`);
            utils.showModal('customer-details-modal', {
                title: `Customer: ${customer.name}`,
                content: this.generateCustomerDetailsHTML(customer)
            });
        } catch (error) {
            console.error('Error loading customer:', error);
            utils.showNotification('Failed to load customer details', 'error');
        }
    }

    generateCustomerDetailsHTML(customer) {
        return `
            <div class="customer-details">
                <div class="detail-section">
                    <h4>Contact Information</h4>
                    <p><strong>Email:</strong> ${customer.email}</p>
                    <p><strong>Phone:</strong> ${customer.phone}</p>
                    <p><strong>Address:</strong> ${customer.address}</p>
                </div>
                
                <div class="detail-section">
                    <h4>Shipment Statistics</h4>
                    <p>Total Shipments: ${customer.shipmentCount || 0}</p>
                    <p>Active Shipments: ${customer.activeShipments || 0}</p>
                </div>
            </div>
        `;
    }

    logout() {
        auth.logout();
    }

    redirectToLogin() {
        if (!window.location.href.includes('login.html')) {
            window.location.href = 'login.html';
        }
    }
}

// Initialize the application
const app = new LogisticsApp();

// Export for use in other modules
if (typeof module !== 'undefined') {
    module.exports = LogisticsApp;
}