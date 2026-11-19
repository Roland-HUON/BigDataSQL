-- =====================================================================
--  Reset : supprime tout ce que table.sql crée (tables, données, type,
--  fonctions, triggers). À lancer AVANT table.sql pour repartir de zéro.
--  ATTENTION : efface définitivement toutes les données de ces tables.
--  L'extension btree_gist est gardée (inoffensive, table.sql la réutilise).
-- =====================================================================
begin;

drop table if exists
  order_items, orders, promo_codes, promotion_categories, promotion_products,
  promotions, cart_items, carts, prices, variants, product_categories,
  products, categories, brands, addresses, users
  cascade;

drop function if exists check_promo_code()    cascade;
drop function if exists check_category_cycle() cascade;
drop function if exists set_updated_at()      cascade;

drop type if exists order_state cascade;

commit;
