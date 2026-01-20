/**
 * Logistics Platform - Authentication Module
 * Handles user authentication, session management, and authorization
 */

class AuthManager {
    constructor() {
        this.currentUser = null;
        this.token = null;
        this.init();
    }

    init() {
        this.loadStoredAuth();
        this.setupAuthInterceptors();
    }

    loadStoredAuth() {
        const token = localStorage.getItem('authToken');
        const user = localStorage.getItem('user');

        if (token && user) {
            this.token = token;
            this.currentUser = JSON.parse(user);
            
            // Set token in API module
            if (window.api) {
                window.api.setAuthToken(token);
            }
        }
    }

    setupAuthInterceptors() {
        // Intercept fetch requests to add authorization header
        const originalFetch = window.fetch;
        window.fetch = async (...args) => {
            const [url, options = {}] = args;
            
            // Add authorization header if token exists
            if (this.token && !options.skipAuth) {
                options.headers = {
                    ...options.headers,
                    'Authorization': `Bearer ${this.token}`
                };
            }

            const response = await originalFetch(url, options);
            
            // Handle 401 Unauthorized responses
            if (response.status === 401) {
                this.handleUnauthorized();
            }

            return response;
        };
    }

    async login(email, password, rememberMe = false) {
        try {
            const response = await fetch(`${api.baseURL}/auth/login`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ email, password })
            });

            if (!response.ok) {
                throw new Error('Login failed');
            }

            const data = await response.json();
            
            if (data.token && data.user) {
                this.setSession(data.token, data.user, rememberMe);
                utils.showNotification('Login successful!', 'success');
                
                // Redirect to dashboard
                setTimeout(() => {
                    window.location.href = 'index.html';
                }, 1000);
                
                return true;
            } else {
                throw new Error('Invalid response from server');
            }
        } catch (error) {
            console.error('Login error:', error);
            utils.showNotification('Invalid email or password', 'error');
            return false;
        }
    }

    async register(userData) {
        try {
            const response = await fetch(`${api.baseURL}/auth/register`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(userData)
            });

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.message || 'Registration failed');
            }

            const data = await response.json();
            
            if (data.token && data.user) {
                this.setSession(data.token, data.user);
                utils.showNotification('Registration successful!', 'success');
                
                // Redirect to dashboard
                setTimeout(() => {
                    window.location.href = 'index.html';
                }, 1000);
                
                return true;
            }
        } catch (error) {
            console.error('Registration error:', error);
            utils.showNotification(error.message || 'Registration failed', 'error');
            return false;
        }
    }

    setSession(token, user, rememberMe = false) {
        this.token = token;
        this.currentUser = user;

        // Store in localStorage
        if (rememberMe) {
            localStorage.setItem('authToken', token);
            localStorage.setItem('user', JSON.stringify(user));
        } else {
            sessionStorage.setItem('authToken', token);
            sessionStorage.setItem('user', JSON.stringify(user));
        }

        // Set token in API module
        if (window.api) {
            window.api.setAuthToken(token);
        }

        // Update UI
        this.updateAuthUI();
    }

    updateAuthUI() {
        const authElements = document.querySelectorAll('.auth-element');
        
        authElements.forEach(element => {
            const authType = element.dataset.auth;
            
            if (authType === 'logged-in' && this.currentUser) {
                element.style.display = 'block';
                
                // Fill user info
                const nameElement = element.querySelector('.user-name');
                const emailElement = element.querySelector('.user-email');
                
                if (nameElement) nameElement.textContent = this.currentUser.name;
                if (emailElement) emailElement.textContent = this.currentUser.email;
                
            } else if (authType === 'logged-out' && !this.currentUser) {
                element.style.display = 'block';
            } else {
                element.style.display = 'none';
            }
        });
    }

    async logout() {
        try {
            // Call logout endpoint
            await fetch(`${api.baseURL}/auth/logout`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.token}`
                }
            });
        } catch (error) {
            console.error('Logout error:', error);
        } finally {
            this.clearSession();
            utils.showNotification('Logged out successfully', 'success');
            
            // Redirect to login page
            setTimeout(() => {
                window.location.href = 'login.html';
            }, 500);
        }
    }

    clearSession() {
        this.token = null;
        this.currentUser = null;
        
        // Clear all storage
        localStorage.removeItem('authToken');
        localStorage.removeItem('user');
        sessionStorage.removeItem('authToken');
        sessionStorage.removeItem('user');
        
        // Clear API token
        if (window.api) {
            window.api.clearAuthToken();
        }
        
        // Update UI
        this.updateAuthUI();
    }

    handleUnauthorized() {
        utils.showNotification('Session expired. Please login again.', 'warning');
        this.clearSession();
        
        // Redirect to login if not already there
        if (!window.location.href.includes('login.html')) {
            setTimeout(() => {
                window.location.href = 'login.html';
            }, 2000);
        }
    }

    async changePassword(currentPassword, newPassword) {
        try {
            const response = await fetch(`${api.baseURL}/auth/change-password`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.token}`
                },
                body: JSON.stringify({
                    currentPassword,
                    newPassword
                })
            });

            if (!response.ok) {
                throw new Error('Password change failed');
            }

            utils.showNotification('Password changed successfully', 'success');
            return true;
        } catch (error) {
            console.error('Password change error:', error);
            utils.showNotification('Failed to change password', 'error');
            return false;
        }
    }

    async resetPassword(email) {
        try {
            const response = await fetch(`${api.baseURL}/auth/reset-password`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ email })
            });

            if (!response.ok) {
                throw new Error('Password reset failed');
            }

            utils.showNotification('Password reset instructions sent to your email', 'success');
            return true;
        } catch (error) {
            console.error('Password reset error:', error);
            utils.showNotification('Failed to send reset instructions', 'error');
            return false;
        }
    }

    isAuthenticated() {
        return !!this.token && !!this.currentUser;
    }

    hasRole(requiredRole) {
        if (!this.currentUser) return false;
        return this.currentUser.role === requiredRole;
    }

    hasPermission(permission) {
        if (!this.currentUser) return false;
        
        // Check user permissions
        const userPermissions = this.currentUser.permissions || [];
        return userPermissions.includes(permission);
    }

    async refreshToken() {
        try {
            const response = await fetch(`${api.baseURL}/auth/refresh`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.token}`
                }
            });

            if (!response.ok) {
                throw new Error('Token refresh failed');
            }

            const data = await response.json();
            this.setSession(data.token, data.user);
            return true;
        } catch (error) {
            console.error('Token refresh error:', error);
            this.handleUnauthorized();
            return false;
        }
    }

    validatePassword(password) {
        const minLength = 8;
        const hasUpperCase = /[A-Z]/.test(password);
        const hasLowerCase = /[a-z]/.test(password);
        const hasNumbers = /\d/.test(password);
        const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);

        return {
            isValid: password.length >= minLength && 
                     hasUpperCase && 
                     hasLowerCase && 
                     hasNumbers && 
                     hasSpecialChar,
            requirements: {
                length: password.length >= minLength,
                upperCase: hasUpperCase,
                lowerCase: hasLowerCase,
                numbers: hasNumbers,
                specialChar: hasSpecialChar
            }
        };
    }
}

// Initialize authentication manager
const auth = new AuthManager();

// Export for use in other modules
if (typeof module !== 'undefined') {
    module.exports = AuthManager;
}