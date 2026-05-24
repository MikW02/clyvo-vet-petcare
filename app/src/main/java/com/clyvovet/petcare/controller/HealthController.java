package com.clyvovet.petcare.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@Tag(name = "Health", description = "Liveness banner -- handy for Azure / load balancer probes")
public class HealthController {

    @GetMapping("/")
    @Operation(summary = "Service banner", description = "Returns a static JSON with app name + status + docs path. Always 200 if the process is up.")
    public Map<String, String> root() {
        return Map.of(
                "app", "Clyvo-vet PetCare API",
                "status", "UP",
                "docs", "/api/pets"
        );
    }
}
