// lib/src/common/managed_service.dart

import 'dart:async';

/// Base interface for any service that can be managed (clients, servers, etc.)
abstract class ManagedService {
  /// Unique identifier for the service
  String get id;

  /// Check if service is currently available
  bool isAvailable();

  /// Connect to the service
  Future<bool> connect();

  /// Disconnect from the service
  Future<bool> disconnect();

  /// Get current service status
  Map<String, dynamic> getStatus();

  /// Execute a capability on the service
  ///
  /// [capabilityName] - Name of the capability to execute
  /// [parameters] - Parameters for the capability
  Future<dynamic> executeCapability(String capabilityName, Map<String, dynamic> parameters);

  /// Check if service has a specific capability
  Future<bool> hasCapability(String capabilityName);

  /// Get a list of available capabilities
  Future<List<String>> getCapabilities();

  /// Get metadata about the service
  Map<String, dynamic> getMetadata();
}

/// Base interface for service managers that handle multiple services
abstract class ServiceManager<T extends ManagedService> {
  /// Add a service to the manager
  void addService(String serviceId, T service, {
    Map<String, dynamic>? routingProperties,
    double weight = 1.0,
  });

  /// Remove a service
  Future<void> removeService(String serviceId);

  /// Get a service by ID
  T? getService(String serviceId);

  /// Select the most appropriate service for a request
  T? selectService(String request, {Map<String, dynamic>? properties});

  /// Get a list of all managed service IDs
  List<String> get serviceIds;

  /// Get count of services
  int get serviceCount;

  /// Close all services
  Future<void> closeAll();
}

/// Base interface for service balancers
abstract class ServiceBalancer {
  /// Register a service with the balancer
  void registerService(String serviceId, {double weight = 1.0});

  /// Unregister a service
  void unregisterService(String serviceId);

  /// Get the next service according to balancing strategy
  String? getNextService();

  /// Update service weights
  void updateServiceWeight(String serviceId, double weight);

  /// Clear all services
  void clear();

  /// Get service statistics
  Map<String, Map<String, dynamic>> getServiceStats();
}

/// Base interface for service routers
abstract class ServiceRouter {
  /// Register a service with routing properties
  void registerService(String serviceId, Map<String, dynamic> properties);

  /// Unregister a service
  void unregisterService(String serviceId);

  /// Find appropriate service for request
  String? routeRequest(String request, [Map<String, dynamic>? requestProperties]);

  /// Set routing strategy
  void setRoutingStrategy(RoutingStrategy strategy);

  /// Get service properties
  Map<String, dynamic>? getServiceProperties(String serviceId);

  /// Get all services with specific property
  List<String> getServicesWithProperty(String property, [dynamic value]);

  /// Clear all registered services
  void clear();
}

/// Routing strategy options
enum RoutingStrategy {
  simple,        // Basic keyword matching
  weighted,      // Score-based routing with weights
  propertyBased, // Specific property matching
  adaptive       // Dynamic strategy based on request
}

/// Base interface for service pools
abstract class ServicePool<T> {
  /// Register a service factory
  void registerServiceFactory(String serviceType, ServiceFactory<T> factory, {int? maxPoolSize});

  /// Set maximum pool size for a service type
  void setMaxPoolSize(String serviceType, int size);

  /// Get a service from the pool
  Future<T> getService(String serviceType, {Duration? timeout});

  /// Return a service to the pool
  void releaseService(String serviceType, T service);

  /// Close all services and clear the pool
  Future<void> close();

  /// Get the current pool statistics
  Map<String, Map<String, int>> getPoolStats();
}

/// Factory interface for creating services
abstract class ServiceFactory<T> {
  /// Create a new service
  Future<T> createService();
}