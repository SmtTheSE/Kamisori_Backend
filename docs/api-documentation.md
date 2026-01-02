# Kamisori Backend API Documentation

This document provides a complete overview of all API endpoints available in the Kamisori Backend system, designed to help frontend developers understand how to interact with the system effectively.

## Authentication

### Login & Registration
- **Endpoint**: `POST /auth/login`
- **Description**: Authenticate user credentials
- **Parameters**:
  - email (string): User's email address
  - password (string): User's password
- **Authentication**: None (public endpoint)
- **Response**: 
  - 200 OK: Returns authentication token and user info
  - 401 Unauthorized: Invalid credentials

### Google OAuth
- **Endpoint**: `GET /auth/google`
- **Description**: Initiate Google OAuth flow
- **Authentication**: None (public endpoint)
- **Flow**: Redirects to Google OAuth page → After approval, redirects back to callback URL

## Products

### Get All Products
- **Endpoint**: `GET /products`
- **Description**: Retrieve all products with pagination
- **Parameters**:
  - limit (integer, optional): Number of products to return (default: 10)
  - offset (integer, optional): Offset for pagination (default: 0)
  - category_id (integer, optional): Filter by product category
  - season (string, optional): Filter by season (e.g., "spring", "summer")
  - year (integer, optional): Filter by year
- **Authentication**: Required (user must be authenticated)
- **Response**:
  - 200 OK: Array of products with metadata
  - 401 Unauthorized: Authentication required

### Get Product by ID
- **Endpoint**: `GET /products/{productId}`
- **Description**: Retrieve specific product details
- **Parameters**:
  - productId (path): ID of the product to retrieve
- **Authentication**: Required
- **Response**:
  - 200 OK: Product object with full details
  - 404 Not Found: Product not found

### Create Product
- **Endpoint**: `POST /products`
- **Description**: Create a new product (admin only)
- **Parameters**:
  - name (string): Product name
  - description (string): Product description
  - price (decimal): Product price
  - category_id (integer): Category ID
  - season (string): Season (e.g., "spring", "summer")
  - year (integer): Year
  - images (array): Array of image URLs or file paths
- **Authentication**: Admin role required
- **Response**:
  - 201 Created: New product created successfully
  - 403 Forbidden: Not authorized to create products

### Update Product
- **Endpoint**: `PUT /products/{productId}`
- **Description**: Update existing product (admin only)
- **Parameters**:
  - productId (path): ID of product to update
  - name (string): Updated product name
  - description (string): Updated description
  - price (decimal): Updated price
  - category_id (integer): Updated category ID
  - season (string): Updated season
  - year (integer): Updated year
  - images (array): Updated array of image URLs
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Product updated successfully
  - 404 Not Found: Product not found
  - 403 Forbidden: Not authorized to update products

### Delete Product
- **Endpoint**: `DELETE /products/{productId}`
- **Description**: Delete a product (admin only)
- **Parameters**:
  - productId (path): ID of product to delete
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Product deleted successfully
  - 404 Not Found: Product not found
  - 403 Forbidden: Not authorized to delete products

## Categories

### Get All Categories
- **Endpoint**: `GET /categories`
- **Description**: Retrieve all product categories
- **Parameters**: None
- **Authentication**: Required
- **Response**:
  - 200 OK: Array of categories
  - 401 Unauthorized: Authentication required

### Get Category by ID
- **Endpoint**: `GET /categories/{categoryId}`
- **Description**: Retrieve specific category details
- **Parameters**:
  - categoryId (path): ID of the category to retrieve
- **Authentication**: Required
- **Response**:
  - 200 OK: Category object
  - 404 Not Found: Category not found

## Shopping Cart

### Add Item to Cart
- **Endpoint**: `POST /cart/items`
- **Description**: Add a product to the user's shopping cart
- **Parameters**:
  - product_id (integer): ID of the product to add
  - quantity (integer): Quantity to add (default: 1)
- **Authentication**: Required
- **Response**:
  - 201 Created: Item added to cart
  - 400 Bad Request: Invalid parameters
  - 401 Unauthorized: Authentication required

### Get Cart Items
- **Endpoint**: `GET /cart/items`
- **Description**: Retrieve all items in the current user's cart
- **Parameters**: None
- **Authentication**: Required
- **Response**:
  - 200 OK: Array of cart items with calculated totals
  - 401 Unauthorized: Authentication required

### Update Cart Item
- **Endpoint**: `PUT /cart/items/{itemId}`
- **Description**: Update quantity of an item in the cart
- **Parameters**:
  - itemId (path): ID of the cart item to update
  - quantity (integer): New quantity
- **Authentication**: Required
- **Response**:
  - 200 OK: Item updated successfully
  - 404 Not Found: Item not found
  - 401 Unauthorized: Authentication required

### Remove Cart Item
- **Endpoint**: `DELETE /cart/items/{itemId}`
- **Description**: Remove an item from the cart
- **Parameters**:
  - itemId (path): ID of the cart item to remove
- **Authentication**: Required
- **Response**:
  - 200 OK: Item removed successfully
  - 404 Not Found: Item not found
  - 401 Unauthorized: Authentication required

### Clear Cart
- **Endpoint**: `DELETE /cart`
- **Description**: Clear all items from the cart
- **Parameters**: None
- **Authentication**: Required
- **Response**:
  - 200 OK: Cart cleared successfully
  - 401 Unauthorized: Authentication required

## Orders

### Create Order
- **Endpoint**: `POST /orders`
- **Description**: Create a new order from cart items
- **Parameters**:
  - delivery_address_id (integer): ID of the delivery address
  - payment_method (string): Payment method (e.g., "kbz_pay")
  - notes (string, optional): Additional notes for the order
- **Authentication**: Required
- **Response**:
  - 201 Created: Order created successfully
  - 400 Bad Request: Invalid parameters
  - 401 Unauthorized: Authentication required

### Get Order by ID
- **Endpoint**: `GET /orders/{orderId}`
- **Description**: Retrieve specific order details
- **Parameters**:
  - orderId (path): ID of the order to retrieve
- **Authentication**: Required
- **Response**:
  - 200 OK: Order object with all details
  - 404 Not Found: Order not found
  - 401 Unauthorized: Authentication required

### Get User Orders
- **Endpoint**: `GET /orders`
- **Description**: Retrieve all orders for the current user
- **Parameters**:
  - status (string, optional): Filter by order status (e.g., "pending", "confirmed", "shipped", "delivered")
  - limit (integer, optional): Number of orders to return
  - offset (integer, optional): Offset for pagination
- **Authentication**: Required
- **Response**:
  - 200 OK: Array of orders
  - 401 Unauthorized: Authentication required

### Update Order Status (Admin Only)
- **Endpoint**: `PUT /orders/{orderId}/status`
- **Description**: Update order status (admin only)
- **Parameters**:
  - orderId (path): ID of the order to update
  - status (string): New status (e.g., "confirmed", "shipped", "delivered", "cancelled")
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Status updated successfully
  - 404 Not Found: Order not found
  - 403 Forbidden: Not authorized to update order status

## Payments

### Upload Payment Slip
- **Endpoint**: `POST /payments/upload-slip`
- **Description**: Upload KBZ Pay payment slip (after order creation)
- **Parameters**:
  - order_id (integer): ID of the order
  - file (binary): Payment slip image file
  - additional_metadata (string, optional): Additional information about the payment
- **Authentication**: Required
- **Response**:
  - 201 Created: Payment slip uploaded successfully
  - 400 Bad Request: Invalid parameters
  - 401 Unauthorized: Authentication required

### Verify Payment (Admin Only)
- **Endpoint**: `PUT /payments/verify/{paymentId}`
- **Description**: Manually verify KBZ Pay payment (admin only)
- **Parameters**:
  - paymentId (path): ID of the payment to verify
  - verified (boolean): Whether the payment is verified
  - verification_notes (string, optional): Notes about the verification
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Payment verification updated
  - 404 Not Found: Payment not found
  - 403 Forbidden: Not authorized to verify payments

## Delivery Addresses

### Get User Addresses
- **Endpoint**: `GET /delivery-addresses`
- **Description**: Retrieve all delivery addresses for the current user
- **Parameters**: None
- **Authentication**: Required
- **Response**:
  - 200 OK: Array of delivery addresses
  - 401 Unauthorized: Authentication required

### Create Delivery Address
- **Endpoint**: `POST /delivery-addresses`
- **Description**: Create a new delivery address
- **Parameters**:
  - customer_name (string): Full name of the recipient
  - phone (string): Phone number
  - address_line_1 (string): First line of address
  - address_line_2 (string, optional): Second line of address
  - city (string): City
  - postal_code (string): Postal code
  - country (string): Country
- **Authentication**: Required
- **Response**:
  - 201 Created: Address created successfully
  - 400 Bad Request: Invalid parameters
  - 401 Unauthorized: Authentication required

### Update Delivery Address
- **Endpoint**: `PUT /delivery-addresses/{addressId}`
- **Description**: Update existing delivery address
- **Parameters**:
  - addressId (path): ID of the address to update
  - customer_name (string): Updated full name
  - phone (string): Updated phone number
  - address_line_1 (string): Updated first line of address
  - address_line_2 (string, optional): Updated second line of address
  - city (string): Updated city
  - postal_code (string): Updated postal code
  - country (string): Updated country
- **Authentication**: Required
- **Response**:
  - 200 OK: Address updated successfully
  - 404 Not Found: Address not found
  - 401 Unauthorized: Authentication required

### Delete Delivery Address
- **Endpoint**: `DELETE /delivery-addresses/{addressId}`
- **Description**: Delete a delivery address
- **Parameters**:
  - addressId (path): ID of the address to delete
- **Authentication**: Required
- **Response**:
  - 200 OK: Address deleted successfully
  - 404 Not Found: Address not found
  - 401 Unauthorized: Authentication required

## Admin Dashboard

### Get All Orders (Admin Only)
- **Endpoint**: `GET /admin/orders`
- **Description**: Retrieve all orders with filtering options (admin only)
- **Parameters**:
  - status (string, optional): Filter by order status
  - customer_email (string, optional): Filter by customer email
  - date_range (string, optional): Date range filter (format: "YYYY-MM-DD to YYYY-MM-DD")
  - limit (integer, optional): Number of orders to return
  - offset (integer, optional): Offset for pagination
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Array of orders with detailed information
  - 401 Unauthorized: Authentication required

### Get All Users (Admin Only)
- **Endpoint**: `GET /admin/users`
- **Description**: Retrieve all users (admin only)
- **Parameters**:
  - role (string, optional): Filter by user role (e.g., "customer", "admin")
  - email (string, optional): Filter by email
  - limit (integer, optional): Number of users to return
  - offset (integer, optional): Offset for pagination
- **Authentication**: Admin role required
- **Response**:
  - 200 OK: Array of users
  - 401 Unauthorized: Authentication required

### Create Admin User (Admin Only)
- **Endpoint**: `POST /admin/users`
- **Description**: Create a new admin user (admin only)
- **Parameters**:
  - email (string): Email address of the new admin
  - password (string): Password for the new admin
- **Authentication**: Admin role required
- **Response**:
  - 201 Created: Admin user created successfully
  - 400 Bad Request: Invalid parameters
  - 403 Forbidden: Not authorized to create admin users

## Error Handling

All endpoints follow consistent error response format: