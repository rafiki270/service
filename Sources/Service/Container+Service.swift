import Async
import Foundation

extension Container {
    /// Returns or creates a service for the given type.
    ///
    /// If a protocol is supplied, a service conforming
    /// to the protocol will be returned.
    public func make<Interface, Client>(
        _ interface: Interface.Type = Interface.self,
        for client: Client.Type
    ) throws -> Interface {
        // check if we've previously resolved this service
        if let service = try serviceCache.get(Interface.self, for: Client.self) {
            return service
        }

        do {
            // resolve the service and cache it
            let service = try unsafeMake(Interface.self, for: Client.self) as! Interface
            serviceCache.set(.service(service), Interface.self, for: Client.self)
            return service
        } catch {
            // cache the error
            serviceCache.set(.error(error), Interface.self, for: Client.self)
            throw error
        }
    }

    /// Returns or creates a service for the given type.
    /// If the service has already been requested once,
    /// the previous result for the interface and client is returned.
    ///
    /// This method accepts and returns Any.
    ///
    /// Use .make() for the safe method.
    internal func unsafeMake(
        _ interface: Any.Type,
        for client: Any.Type
    ) throws -> Any {
        // find all available service types that match the requested type.
        let available = services.factories(supporting: interface)

        let chosen: ServiceFactory

        if available.count > 1 {
            // multiple services are available,
            // we will need to disambiguate
            chosen = try config.choose(
                from: available,
                interface: interface,
                for: self,
                neededBy: client
            )
        } else if available.count == 0 {
            // no services are available matching
            // the type requested.
            throw ServiceError(
                identifier: "make",
                reason: "No services are available for '\(interface)'.",
                suggestedFixes: [
                    "Register a service for '\(interface)'.",
                    "`services.register(\(interface).self) { ... }`."
                ]
            )
        } else {
            // only one service matches, no need to disambiguate.
            // let's use it!
            chosen = available[0]
        }

        try config.approve(
            chosen: chosen,
            interface: interface,
            for: self,
            neededBy: client
        )

        // attempt to fetch singleton from cache
        if let singleton = try serviceCache.getSingleton(chosen.serviceType) {
            return singleton
        } else {
            do {
                let item = try chosen.makeService(for: self)
                serviceCache.setSingleton(.service(item), type: chosen.serviceType)
                return item
            } catch {
                serviceCache.setSingleton(.error(error), type: chosen.serviceType)
                throw error
            }
        }
    }
}

// MARK: Service Utilities

extension Services {
    fileprivate func factories(supporting interface: Any.Type) -> [ServiceFactory] {
        var factories = [ServiceFactory]()
        
        for factory in self.factories where factory.serviceType == interface || factory.serviceSupports.contains(where: { $0 == interface }) {
            factories.append(factory)
        }
        
        return factories
    }
}
