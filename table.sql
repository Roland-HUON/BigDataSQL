begin;

create schema if not exists extensions;  -- existe déjà sur Supabase, nécessaire sur un Postgres classique
create extension if not exists btree_gist with schema extensions;

create type order_state as enum ('pending', 'paid', 'shipped', 'delivered', 'cancelled');

create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Règle : un client ne se supprime pas, il se désactive (deactivated_at = now()).
-- Supprimer un client supprimerait ses codes promo réservés ; si une commande a
-- utilisé l'un d'eux, la base bloque la suppression (orders.promo_code_id restrict).
-- La désactivation garde intacts ses commandes et ses codes.
create table users (
  id                 bigint generated always as identity primary key,
  first_name         text        not null,
  last_name          text        not null,
  email              text        not null unique check (email = lower(email)),  -- stocké en minuscules => Alice@x.fr = alice@x.fr
  phone              text,
  created_at         timestamptz not null default now(),
  last_connection_at timestamptz,
  deactivated_at     timestamptz,  -- NULL = compte actif
  constraint users_deactivated_after_created check (deactivated_at is null or deactivated_at >= created_at)
);

create table addresses (
  id               bigint generated always as identity primary key,
  user_id          bigint      not null references users(id) on delete cascade,
  address          text        not null,  -- numéro et rue
  postal_code      text        not null,
  city             text        not null,
  place            text,
  country          char(2)     not null check (country ~ '^[A-Z]{2}$'),  -- code ISO 3166-1 : FR, BE, US...
  default_delivery boolean     not null default false,
  updated_at       timestamptz not null default now()
);
create index on addresses (user_id);

create unique index addresses_one_default_per_user
  on addresses (user_id) where default_delivery;

create trigger addresses_updated_at before update on addresses
  for each row execute function set_updated_at();

create table brands (
  id   bigint generated always as identity primary key,
  name text not null unique
);

create table categories (
  id        bigint generated always as identity primary key,
  parent_id bigint references categories(id) on delete set null,  -- NULL = catégorie racine
  name      text   not null,
  constraint categories_not_own_parent check (parent_id is null or parent_id <> id)
);
create index on categories (parent_id);

-- Empêche les boucles dans l'arborescence (A -> B -> A)
create or replace function check_category_cycle() returns trigger
language plpgsql as $$
begin
  if new.parent_id is not null and exists (
    with recursive ancestors(id) as (
      select new.parent_id
      union
      select c.parent_id from categories c join ancestors a on c.id = a.id
      where c.parent_id is not null
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'Catégorie % : boucle dans l''arborescence', new.id;
  end if;
  return new;
end;
$$;

create trigger categories_no_cycle
  before insert or update of parent_id on categories
  for each row execute function check_category_cycle();

create table products (
  id                   bigint generated always as identity primary key,
  name                 text   not null,
  description          text,
  commercial_reference text   not null unique,
  brand_id             bigint not null references brands(id) on delete restrict
);
create index on products (brand_id);

create table product_categories (
  id          bigint generated always as identity primary key,
  product_id  bigint not null references products(id)   on delete cascade,
  category_id bigint not null references categories(id) on delete cascade,
  unique (product_id, category_id)
);
create index on product_categories (category_id);

create table variants (
  id         bigint generated always as identity primary key,
  product_id bigint      not null references products(id) on delete cascade,
  size       text,
  color      text,
  reference  text        not null unique,
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz  -- NULL = variante active (en vente) ; on désactive au lieu de supprimer
);
create index on variants (product_id);

create trigger variants_updated_at before update on variants
  for each row execute function set_updated_at();

create table prices (
  id          bigint generated always as identity primary key,
  variant_id  bigint        not null references variants(id) on delete cascade,
  currency    char(3)       not null check (currency ~ '^[A-Z]{3}$'),
  amount      numeric(12,2) not null check (amount >= 0),
  market      text          not null,
  valid_from  timestamptz   not null default now(),
  valid_to    timestamptz,
  constraint prices_valid_period check (valid_to is null or valid_to > valid_from),
  constraint prices_no_overlap exclude using gist (
    variant_id with =,
    currency   with =,
    market     with =,
    tstzrange(valid_from, valid_to) with &&
  )
);
create index on prices (variant_id);

create table carts (
  id         bigint generated always as identity primary key,
  user_id    bigint      not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on carts (user_id);

create trigger carts_updated_at before update on carts
  for each row execute function set_updated_at();

create table cart_items (
  id         bigint generated always as identity primary key,
  cart_id    bigint  not null references carts(id)    on delete cascade,
  variant_id bigint  not null references variants(id) on delete cascade,
  quantity   integer not null check (quantity > 0),
  unique (cart_id, variant_id)
);
create index on cart_items (variant_id);

create table promotions (
  id             bigint generated always as identity primary key,
  reduction  numeric(5,2) not null check (reduction > 0 and reduction <= 100),
  date_start timestamptz  not null,
  date_end   timestamptz  not null,
  max_uses   integer      check (max_uses > 0),
  constraint promotions_valid_period check (date_end > date_start)
);

create table promotion_products (
  id           bigint generated always as identity primary key,
  promotion_id bigint not null references promotions(id) on delete cascade,
  product_id   bigint not null references products(id)   on delete cascade,
  unique (promotion_id, product_id)
);
create index on promotion_products (product_id);

create table promotion_categories (
  id           bigint generated always as identity primary key,
  promotion_id bigint not null references promotions(id) on delete cascade,
  category_id  bigint not null references categories(id) on delete cascade,
  unique (promotion_id, category_id)
);
create index on promotion_categories (category_id);

create table promo_codes (
  id                bigint generated always as identity primary key,
  promotion_id      bigint  not null references promotions(id) on delete cascade,
  code              text    not null unique,
  is_one_person     boolean not null default false,
  user_id           bigint  references users(id) on delete cascade,
  max_users         integer check (max_users > 0),
  max_uses_per_user integer check (max_uses_per_user > 0),
  constraint promo_codes_reserved_user check (not is_one_person or user_id is not null)
);
create index on promo_codes (promotion_id);
create index on promo_codes (user_id);

create table orders (
  id               bigint generated always as identity primary key,
  public_id        uuid        not null unique default gen_random_uuid(),
  user_id          bigint      references users(id) on delete set null,
  first_name       text        not null,
  last_name        text        not null,
  email            text        not null,
  shipping_address     text    not null,  -- numéro et rue
  shipping_postal_code text    not null,
  shipping_city        text    not null,
  shipping_place   text,
  shipping_country char(2)     not null check (shipping_country ~ '^[A-Z]{2}$'),
  order_date       timestamptz not null default now(),
  state            order_state not null default 'pending',
  currency         char(3)     not null check (currency ~ '^[A-Z]{3}$'),
  promo_code_id    bigint      references promo_codes(id) on delete restrict
);
create index on orders (user_id);
create index on orders (email);
create index on orders (promo_code_id);

create table order_items (
  id         bigint generated always as identity primary key,
  order_id   bigint        not null references orders(id)   on delete cascade,
  variant_id bigint        not null references variants(id) on delete restrict,
  quantity   integer       not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  discount   numeric(12,2) check (discount >= 0),
  constraint order_items_discount_max check (discount <= quantity * unit_price),
  unique (order_id, variant_id)
);
create index on order_items (variant_id);

-- ---------------------------------------------------------------------
--  Vérification des règles des codes promo à la création d'une commande
-- ---------------------------------------------------------------------
create or replace function check_promo_code() returns trigger
language plpgsql as $$
declare
  c promo_codes%rowtype;
  p promotions%rowtype;
  n integer;
begin
  if new.promo_code_id is null then
    return new;
  end if;

  -- En mise à jour, on ne revérifie que si le code change ou si une commande annulée est réactivée
  if tg_op = 'UPDATE'
     and new.promo_code_id is not distinct from old.promo_code_id
     and old.state <> 'cancelled' then
    return new;
  end if;

  select * into c from promo_codes where id = new.promo_code_id;
  -- Verrou sur la promotion : deux commandes simultanées ne peuvent pas dépasser les limites
  select * into p from promotions  where id = c.promotion_id for update;

  -- Dates de validité
  if new.order_date < p.date_start or new.order_date > p.date_end then
    raise exception 'Code promo % hors période de validité', c.code;
  end if;

  -- Code réservé à une seule personne
  if c.is_one_person and new.user_id is distinct from c.user_id then
    raise exception 'Code promo % réservé à un autre client', c.code;
  end if;

  -- Une commande annulée ne consomme pas d'utilisation : pas de contrôle des limites
  if new.state = 'cancelled' then
    return new;
  end if;

  -- Nombre maximal d'utilisations de la promotion (tous codes confondus)
  if p.max_uses is not null then
    select count(*) into n
    from orders o join promo_codes pc on pc.id = o.promo_code_id
    where pc.promotion_id = p.id and o.state <> 'cancelled' and o.id <> new.id;
    if n >= p.max_uses then
      raise exception 'Promotion épuisée (% utilisations max)', p.max_uses;
    end if;
  end if;

  -- Nombre d'utilisations par client (compte ou e-mail pour un invité)
  if c.max_uses_per_user is not null then
    select count(*) into n
    from orders o
    where o.promo_code_id = c.id and o.state <> 'cancelled' and o.id <> new.id
      and (o.user_id = new.user_id or lower(o.email) = lower(new.email));
    if n >= c.max_uses_per_user then
      raise exception 'Code promo % déjà utilisé le nombre maximal de fois par ce client', c.code;
    end if;
  end if;

  -- Nombre de clients différents
  if c.max_users is not null then
    select count(distinct coalesce(o.user_id::text, lower(o.email))) into n
    from orders o
    where o.promo_code_id = c.id and o.state <> 'cancelled' and o.id <> new.id
      -- coalesce : avec un invité, user_id est NULL et "not (NULL or false)" excluait la ligne
      and not (coalesce(o.user_id = new.user_id, false) or lower(o.email) = lower(new.email));
    if n >= c.max_users then
      raise exception 'Code promo % : nombre maximal de clients atteint', c.code;
    end if;
  end if;

  return new;
end;
$$;

create trigger orders_check_promo_code
  before insert or update of promo_code_id, state on orders
  for each row execute function check_promo_code();

commit;