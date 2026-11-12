-- =============================================================================
-- Vitriin — Statut « programmée » des publications (12 novembre 2026, MOD-082)
-- =============================================================================
-- Migration séparée : une valeur d'enum ajoutée ne peut pas servir dans la même
-- transaction (index partiel, contrainte). La suite est dans
-- 20261112170100_publication_scheduler.sql.
-- Retour arrière : une valeur d'enum ne se retire pas. Elle reste sans effet
-- si plus aucune ligne ne la porte (voir la migration inverse du planificateur).
-- =============================================================================

alter type public.publication_status add value if not exists 'scheduled';
