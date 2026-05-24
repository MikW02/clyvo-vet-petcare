package com.clyvovet.petcare.repository;

import com.clyvovet.petcare.model.Pet;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PetRepository extends JpaRepository<Pet, Long> {
    List<Pet> findBySpeciesIgnoreCase(String species);
    List<Pet> findByOwnerNameContainingIgnoreCase(String ownerName);
}
