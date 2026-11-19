-- =====================================================================
--  Seeder : jeu de données de test pour table.sql
--  À exécuter APRÈS table.sql. Réexécutable : vide les tables d'abord.
--  Volumes (environ) : users 500, addresses ~1000, brands 50,
--  categories 60, products 300, product_categories ~600, variants 1800,
--  prices ~5400, carts 200, cart_items ~600, promotions 60,
--  promotion_products ~150, promotion_categories ~60, promo_codes 120,
--  orders 2000, order_items ~6000
-- =====================================================================
begin;

-- Vide toutes les tables et remet les compteurs d'id à 1
truncate users, addresses, brands, categories, products, product_categories,
         variants, prices, carts, cart_items, promotions, promotion_products,
         promotion_categories, promo_codes, orders, order_items
  restart identity cascade;

select setseed(0.42);  -- données aléatoires mais identiques à chaque exécution

-- ---------------------------------------------------------------------
--  users (500)
-- ---------------------------------------------------------------------
with fn as (select array['Lucas','Emma','Hugo','Léa','Louis','Chloé','Gabriel','Manon','Arthur','Camille',
                         'Jules','Sarah','Adam','Inès','Raphaël','Jade','Nathan','Louise','Tom','Alice'] a),
     ln as (select array['Martin','Bernard','Dubois','Thomas','Robert','Richard','Petit','Durand','Leroy','Moreau',
                         'Simon','Laurent','Lefebvre','Michel','Garcia','David','Bertrand','Roux','Vincent','Fournier'] a)
insert into users (first_name, last_name, email, phone, created_at, last_connection_at, deactivated_at)
select f, l,
       lower(translate(f, 'éèëï', 'eeei') || '.' || l || i || '@example.com'),
       case when i % 4 = 0 then null else '06' || lpad((floor(random() * 1e8))::int::text, 8, '0') end,
       c,
       case when i % 10 = 0 then null else c + random() * (now() - c) end,
       case when i % 25 = 0 then c + (0.5 + random() * 0.5) * (now() - c) end  -- 1 client sur 25 désactivé
from generate_series(1, 500) i,
     lateral (select (select a from fn)[1 + (i * 7) % 20] f,
                     (select a from ln)[1 + (i * 13) % 20] l,
                     now() - (random() * 1000) * interval '1 day' c) x;

-- ---------------------------------------------------------------------
--  addresses (1 à 3 par utilisateur, la 1re est l'adresse par défaut pour 90 %)
-- ---------------------------------------------------------------------
-- villes et pays associés (même position dans les deux tableaux)
with cities as (select array['75001 Paris','69002 Lyon','13001 Marseille','33000 Bordeaux','59000 Lille',
                             '31000 Toulouse','44000 Nantes','67000 Strasbourg','1000 Bruxelles','1201 Genève'] a,
                       array['FR','FR','FR','FR','FR','FR','FR','FR','BE','CH'] c),
     streets as (select array['rue de la Paix','avenue Victor Hugo','boulevard Voltaire','rue Nationale',
                              'rue des Lilas','place de la République','rue du Moulin','allée des Pins'] a)
insert into addresses (user_id, address, place, country, default_delivery)
select u.id,
       (1 + floor(random() * 150))::int || ' ' || (select a from streets)[1 + (u.id + n) % 8] || ', '
         || (select a from cities)[1 + (u.id * 3 + n) % 10],
       (array['Maison','Travail','Parents', null])[n],
       (select c from cities)[1 + (u.id * 3 + n) % 10],
       n = 1 and u.id % 10 <> 0
from users u
cross join lateral generate_series(1, 1 + (u.id % 3)) n;

-- ---------------------------------------------------------------------
--  brands (50)
-- ---------------------------------------------------------------------
insert into brands (name)
select (array['Nova','Atlas','Zenith','Orion','Vega','Lumen','Nordik','Solaris','Terra','Kairo'])[1 + (i - 1) % 10]
       || ' ' || (array['Sport','Wear','Studio','Outdoor','Paris'])[1 + (i - 1) / 10]
from generate_series(1, 50) i;

-- ---------------------------------------------------------------------
--  categories (10 racines + 50 sous-catégories)
-- ---------------------------------------------------------------------
insert into categories (name)
select unnest(array['Homme','Femme','Enfant','Chaussures','Sport','Accessoires','Outdoor','Bébé','Maison','Soldes']);

insert into categories (parent_id, name)
select 1 + (i - 1) % 10,
       (array['T-shirts','Pantalons','Vestes','Pulls','Sneakers','Running','Sacs','Casquettes','Chaussettes','Shorts'])[1 + ((i - 1) / 10) * 2 + i % 2]
         || ' ' || (array['Homme','Femme','Enfant','Chaussures','Sport','Accessoires','Outdoor','Bébé','Maison','Soldes'])[1 + (i - 1) % 10]
from generate_series(1, 50) i;

-- ---------------------------------------------------------------------
--  products (300)
-- ---------------------------------------------------------------------
insert into products (name, description, commercial_reference, brand_id)
select t || ' ' || adj,
       case when i % 5 = 0 then null else t || ' ' || lower(adj) || ', confortable et résistant.' end,
       'REF-' || lpad(i::text, 5, '0'),
       1 + floor(random() * 50)::int
from generate_series(1, 300) i,
     lateral (select (array['T-shirt','Jean','Veste','Pull','Sneaker','Chaussure de running','Sac à dos',
                            'Casquette','Short','Sweat'])[1 + i % 10] t,
                     (array['Classic','Urban','Pro','Lite','Max','Vintage','Eco','Flex','Air','Storm',
                            'Trail','Street','Premium','Basic','Edge'])[1 + (i / 10) % 15] adj) x;

-- ---------------------------------------------------------------------
--  product_categories (1 à 3 catégories par produit)
-- ---------------------------------------------------------------------
insert into product_categories (product_id, category_id)
select p.id, 11 + floor(random() * 50)::int
from products p cross join lateral generate_series(1, 1 + (p.id % 3)) n
on conflict do nothing;

-- ---------------------------------------------------------------------
--  variants (6 par produit : 3 tailles x 2 couleurs = 1800)
-- ---------------------------------------------------------------------
insert into variants (product_id, size, color, reference)
select p.id, s, c, p.commercial_reference || '-' || s || '-' || upper(left(c, 3))
from products p
cross join lateral (select (array['XS','S','M','L','XL','XXL'])[1 + (p.id + k) % 6] s from generate_series(0, 2) k) sizes
cross join lateral (select (array['noir','blanc','bleu','rouge','vert','gris'])[1 + (p.id + k * 3) % 6] c from generate_series(0, 1) k) colors;

-- ---------------------------------------------------------------------
--  prices : par variante
--    FR/EUR : ancien prix (3 ans -> 6 mois) puis prix actuel (sans fin)
--    BE/EUR : prix unique sans fin
--    US/USD : 1 variante sur 2
-- ---------------------------------------------------------------------
with base as (
  select v.id, round((10 + random() * 140)::numeric, 2) amount from variants v
)
insert into prices (variant_id, currency, amount, market, valid_from, valid_to)
select id, 'EUR', amount, 'FR', date_trunc('day', now()) - interval '3 years', date_trunc('day', now()) - interval '6 months' from base
union all
select id, 'EUR', round(amount * (0.9 + random() * 0.2)::numeric, 2), 'FR', date_trunc('day', now()) - interval '6 months', null from base
union all
select id, 'EUR', round(amount * 1.02, 2), 'BE', date_trunc('day', now()) - interval '3 years', null from base
union all
select id, 'USD', round(amount * 1.1, 2), 'US', date_trunc('day', now()) - interval '3 years', null from base where id % 2 = 0;

-- ---------------------------------------------------------------------
--  carts (200) + cart_items (1 à 5 articles par panier)
-- ---------------------------------------------------------------------
insert into carts (user_id, created_at)
select u.id, now() - random() * interval '60 days'
from users u where u.id % 5 <> 0 and u.id <= 250;

insert into cart_items (cart_id, variant_id, quantity)
select c.id, 1 + floor(random() * 1800)::int, 1 + floor(random() * 3)::int
from carts c cross join lateral generate_series(1, 1 + (c.id % 5)) n
on conflict do nothing;

-- ---------------------------------------------------------------------
--  promotions (60) : réparties sur 2 ans, quelques-unes à venir
--  1 sur 5 limitée à 40 utilisations
-- ---------------------------------------------------------------------
insert into promotions (reduction, date_start, date_end, max_uses)
select (array[5,10,15,20,25,30,40,50])[1 + i % 8],
       d, d + (7 + floor(random() * 83)::int) * interval '1 day',
       case when i % 5 = 0 then 40 end
from generate_series(1, 60) i,
     lateral (select now() - (730 - i * 12.5) * interval '1 day' d) x;

insert into promotion_products (promotion_id, product_id)
select p.id, 1 + floor(random() * 300)::int
from promotions p cross join lateral generate_series(1, 1 + (p.id % 4)) n
on conflict do nothing;

insert into promotion_categories (promotion_id, category_id)
select p.id, 1 + floor(random() * 60)::int
from promotions p where p.id % 3 <> 0
union all
select p.id, 1 + floor(random() * 10)::int
from promotions p where p.id % 4 = 0
on conflict do nothing;

-- ---------------------------------------------------------------------
--  promo_codes (120 : 2 par promotion)
--    1 sur 10 : réservé à un client
--    1 sur 3  : 1 utilisation max par client
--    1 sur 7  : 15 clients différents max
-- ---------------------------------------------------------------------
insert into promo_codes (promotion_id, code, is_one_person, user_id, max_users, max_uses_per_user)
select 1 + (i - 1) / 2,
       'PROMO' || lpad(i::text, 4, '0'),
       i % 10 = 0,
       case when i % 10 = 0 then 1 + floor(random() * 500)::int end,
       case when i % 7 = 0 then 15 end,
       case when i % 3 = 0 then 1 end
from generate_series(1, 120) i;

-- ---------------------------------------------------------------------
--  orders (2000) + order_items (1 à 5 lignes par commande)
--  Les commandes passent par le trigger check_promo_code : si un code
--  tiré au hasard n'est pas valable, la commande est créée sans code.
-- ---------------------------------------------------------------------
do $$
declare
  i        integer;
  v_user   users%rowtype;
  v_addr   addresses%rowtype;
  v_date   timestamptz;
  v_state  order_state;
  v_code   bigint;
  v_red    numeric;
  v_order  bigint;
  v_email  text;
begin
  for i in 1 .. 2000 loop
    v_date := now() - random() * interval '700 days';

    -- 85 % de clients inscrits, 15 % d'invités
    v_user := null;
    v_addr := null;
    if random() < 0.85 then
      -- seulement un client inscrit et actif à la date de la commande
      select * into v_user from users
      where created_at <= v_date and (deactivated_at is null or deactivated_at > v_date)
      order by random() limit 1;
      select * into v_addr from addresses where user_id = v_user.id order by default_delivery desc, id limit 1;
    end if;
    -- sinon (ou si aucun client n'était actif à cette date) : invité
    v_email := coalesce(v_user.email, 'invite' || (1 + floor(random() * 250))::int || '@example.org');

    -- État selon l'ancienneté
    v_state := case
      when random() < 0.07                      then 'cancelled'
      when v_date < now() - interval '15 days'  then 'delivered'
      when v_date < now() - interval '5 days'   then 'shipped'
      when v_date < now() - interval '1 day'    then 'paid'
      else 'pending' end;

    -- 30 % des commandes tentent un code promo valable à cette date
    v_code := null;
    if random() < 0.30 then
      select pc.id into v_code
      from promo_codes pc join promotions p on p.id = pc.promotion_id
      where v_date between p.date_start and p.date_end
      order by random() limit 1;
    end if;

    begin
      insert into orders (user_id, first_name, last_name, email, shipping_address, shipping_place,
                          shipping_country, order_date, state, currency, promo_code_id)
      values (v_user.id,
              coalesce(v_user.first_name, (array['Paul','Marie','Yanis','Zoé'])[1 + i % 4]),
              coalesce(v_user.last_name,  (array['Blanc','Noir','Morel','Faure'])[1 + i % 4]),
              v_email,
              coalesce(v_addr.address, (1 + i % 120) || ' rue du Commerce, 75015 Paris'),
              v_addr.place, coalesce(v_addr.country, 'FR'), v_date, v_state, 'EUR', v_code)
      returning id into v_order;
    exception when raise_exception then
      -- code refusé par le trigger (épuisé, réservé, déjà utilisé...) => commande sans code
      v_code := null;
      insert into orders (user_id, first_name, last_name, email, shipping_address, shipping_place,
                          shipping_country, order_date, state, currency)
      values (v_user.id,
              coalesce(v_user.first_name, (array['Paul','Marie','Yanis','Zoé'])[1 + i % 4]),
              coalesce(v_user.last_name,  (array['Blanc','Noir','Morel','Faure'])[1 + i % 4]),
              v_email,
              coalesce(v_addr.address, (1 + i % 120) || ' rue du Commerce, 75015 Paris'),
              v_addr.place, coalesce(v_addr.country, 'FR'), v_date, v_state, 'EUR')
      returning id into v_order;
    end;

    select p.reduction into v_red
    from promo_codes pc join promotions p on p.id = pc.promotion_id where pc.id = v_code;

    -- Lignes : prix FR/EUR en vigueur à la date de la commande
    insert into order_items (order_id, variant_id, quantity, unit_price, discount)
    select v_order, x.variant_id, x.qty, pr.amount,
           case when v_red is not null then round(pr.amount * x.qty * v_red / 100, 2) end
    from (select distinct on (variant_id) variant_id, qty
          from (select 1 + floor(random() * 1800)::int variant_id, 1 + floor(random() * 3)::int qty
                from generate_series(1, 1 + floor(random() * 5)::int)) r) x
    join prices pr on pr.variant_id = x.variant_id and pr.market = 'FR' and pr.currency = 'EUR'
                  and pr.valid_from <= v_date and (pr.valid_to is null or pr.valid_to > v_date);
  end loop;
end $$;

commit;

-- Récapitulatif
select 'users' t, count(*) from users union all
select 'addresses', count(*) from addresses union all
select 'brands', count(*) from brands union all
select 'categories', count(*) from categories union all
select 'products', count(*) from products union all
select 'product_categories', count(*) from product_categories union all
select 'variants', count(*) from variants union all
select 'prices', count(*) from prices union all
select 'carts', count(*) from carts union all
select 'cart_items', count(*) from cart_items union all
select 'promotions', count(*) from promotions union all
select 'promotion_products', count(*) from promotion_products union all
select 'promotion_categories', count(*) from promotion_categories union all
select 'promo_codes', count(*) from promo_codes union all
select 'orders', count(*) from orders union all
select 'order_items', count(*) from order_items;
