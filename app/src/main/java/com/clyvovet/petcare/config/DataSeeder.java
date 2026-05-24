package com.clyvovet.petcare.config;

import com.clyvovet.petcare.model.Pet;
import com.clyvovet.petcare.repository.PetRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

/**
 * Re-seeds the PETS table with the same 5 demo rows on every application start.
 * Keeps the UI predictable for testing (Swagger / curl always sees the same data).
 * Drop this bean -- or guard it behind a profile -- before going to production.
 *
 * Non-ASCII letters use \\uXXXX Java escapes (resolved by javac before file
 * encoding matters) so names round-trip cleanly regardless of the build host.
 */
@Configuration
public class DataSeeder {

    @Bean
    CommandLineRunner seedPets(PetRepository repo) {
        return args -> {
            repo.deleteAllInBatch();

            List<Pet> demo = List.of(
                    pet("Rex",      "dog",    "Labrador",  4, "Maria Silva"),
                    pet("Mia",      "cat",    "Siamese",   3, "Joao Souza"),
                    pet("Biscoito", "rabbit", null,        2, "Ana Lima"),
                    pet("Thor",     "dog",    "Husky",     5, "Carla Mendes"),
                    pet("Luna",     "cat",    "Persian",   1, "Pedro Rocha")
            );
            repo.saveAll(demo);
        };
    }

    private static Pet pet(String name, String species, String breed, int age, String owner) {
        Pet p = new Pet();
        p.setName(name);
        p.setSpecies(species);
        p.setBreed(breed);
        p.setAge(age);
        p.setOwnerName(owner);
        return p;
    }
}
