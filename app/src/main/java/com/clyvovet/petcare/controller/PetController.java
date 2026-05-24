package com.clyvovet.petcare.controller;

import com.clyvovet.petcare.model.Pet;
import com.clyvovet.petcare.repository.PetRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/pets")
@Tag(name = "Pets", description = "CRUD of pets managed by Clyvo-vet PetCare")
public class PetController {

    private final PetRepository repository;

    public PetController(PetRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    @Operation(
        summary = "List pets",
        description = "Returns every pet stored. Optional 'species' query param filters case-insensitively (e.g. ?species=dog)."
    )
    @ApiResponse(responseCode = "200", description = "OK -- list returned (may be empty)")
    public List<Pet> list(
            @Parameter(description = "Optional species filter (case-insensitive). Examples: dog, cat, rabbit")
            @RequestParam(required = false) String species) {
        if (species != null && !species.isBlank()) {
            return repository.findBySpeciesIgnoreCase(species);
        }
        return repository.findAll();
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get pet by id")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK -- pet found"),
        @ApiResponse(responseCode = "404", description = "Not Found -- no pet with that id")
    })
    public ResponseEntity<Pet> get(@PathVariable Long id) {
        return repository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    @Operation(
        summary = "Create pet",
        description = "Creates a pet. The 'id' field is ignored on input -- the server generates it."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "Created -- response body is the saved pet; 'Location' header points at /api/pets/{id}"),
        @ApiResponse(responseCode = "400", description = "Bad Request -- payload failed validation (missing name/species/ownerName, negative age, etc.)")
    })
    public ResponseEntity<Pet> create(@Valid @RequestBody Pet pet) {
        pet.setId(null);
        Pet saved = repository.save(pet);
        return ResponseEntity.created(URI.create("/api/pets/" + saved.getId())).body(saved);
    }

    @PutMapping("/{id}")
    @Operation(
        summary = "Replace pet",
        description = "Full update of an existing pet. All fields in the body overwrite the stored ones."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "OK -- pet updated; body is the new state"),
        @ApiResponse(responseCode = "400", description = "Bad Request -- payload failed validation"),
        @ApiResponse(responseCode = "404", description = "Not Found -- no pet with that id")
    })
    public ResponseEntity<Pet> update(@PathVariable Long id, @Valid @RequestBody Pet pet) {
        return repository.findById(id).map(existing -> {
            existing.setName(pet.getName());
            existing.setSpecies(pet.getSpecies());
            existing.setBreed(pet.getBreed());
            existing.setAge(pet.getAge());
            existing.setOwnerName(pet.getOwnerName());
            return ResponseEntity.ok(repository.save(existing));
        }).orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "Delete pet")
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "No Content -- pet deleted; nothing returned in the body"),
        @ApiResponse(responseCode = "404", description = "Not Found -- no pet with that id")
    })
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        if (!repository.existsById(id)) {
            return ResponseEntity.notFound().build();
        }
        repository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
