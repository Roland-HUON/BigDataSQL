-- Défi 1
SELECT o.shipping_country,
  COUNT(DISTINCT o.id) AS nb_orders,
  SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) AS chiffre_affaires,
  ROUND(SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) / COUNT(DISTINCT o.id), 2) AS montant_moyen
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.state IN ('paid', 'shipped', 'delivered')
GROUP BY o.shipping_country
ORDER BY chiffre_affaires DESC;

-- Défi 2
SELECT o.shipping_city,
  COUNT(DISTINCT o.id) AS nb_orders,
  ROUND(SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) / COUNT(DISTINCT o.id), 2) AS average_cart
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.state IN ('paid', 'shipped', 'delivered')
GROUP BY o.shipping_city
HAVING COUNT(DISTINCT o.id) >= 30
ORDER BY average_cart DESC
LIMIT 20;

-- Défi 3
SELECT u.id, u.first_name, u.last_name,
  COUNT(DISTINCT o.id) AS nb_orders,
  SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) AS depense_totale
FROM users u
  JOIN orders o ON o.user_id = u.id
  JOIN order_items i ON i.order_id = o.id
WHERE o.state IN ('paid', 'shipped', 'delivered') AND o.order_date >= NOW() - INTERVAL '12 months'
GROUP BY u.id
ORDER BY nb_orders DESC, depense_totale DESC
LIMIT 50;

-- Défi 4
SELECT v.id, v.reference FROM variants v
WHERE v.deactivated_at IS NULL AND NOT EXISTS (
  SELECT 1 FROM order_items i JOIN orders o ON o.id = i.order_id
  WHERE i.variant_id = v.id AND o.state IN ('paid', 'shipped', 'delivered')
)
ORDER BY v.id;

-- Défi 5
SELECT
  RANK() OVER (ORDER BY SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) DESC) AS rank,
  b.name AS brand,
  SUM(i.quantity) AS quantity_sold,
  SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) AS chiffre_affaires
FROM brands b
  JOIN products p ON p.brand_id = b.id
  JOIN variants v ON v.product_id = p.id
  JOIN order_items i ON i.variant_id = v.id
  JOIN orders o ON o.id = i.order_id
WHERE o.state IN ('paid', 'shipped', 'delivered')
GROUP BY b.id
ORDER BY chiffre_affaires DESC;

-- Défi 7
SELECT u.id, u.first_name, u.last_name, MAX(o.order_date) AS derniere_commande
FROM users u JOIN orders o ON o.user_id = u.id
WHERE u.deactivated_at IS NULL
GROUP BY u.id
HAVING BOOL_OR(o.state IN ('paid', 'shipped', 'delivered')) AND MAX(o.order_date) < NOW() - INTERVAL '180 days'
ORDER BY derniere_commande;

-- Défi 8
SELECT * FROM (
  SELECT 
    o.shipping_country,
    RANK() OVER (PARTITION BY o.shipping_country ORDER BY SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) DESC) AS rank, 
    c.name AS category,
    SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) AS chiffre_affaires
  FROM orders o
    JOIN order_items i ON i.order_id = o.id
    JOIN variants v ON v.id = i.variant_id
    JOIN product_categories pc ON pc.product_id = v.product_id
    JOIN categories c ON c.id = pc.category_id
  WHERE o.state IN ('paid', 'shipped', 'delivered')
  GROUP BY o.shipping_country, c.id
)
WHERE rank = 1
ORDER BY chiffre_affaires DESC;

-- Défi 18
SELECT shipping_country, ca_last_month, ca_in_progress_month, 
  ca_in_progress_month - ca_last_month AS variation_euros,
  ROUND((ca_in_progress_month - ca_last_month) / NULLIF(ca_last_month, 0) * 100, 2) AS variation_pct
FROM (
  SELECT o.shipping_country,
    COALESCE(SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) FILTER (WHERE DATE_TRUNC('month', o.order_date) = DATE_TRUNC('month', NOW()) - INTERVAL '1 month'), 0) AS ca_last_month,
    COALESCE(SUM(i.quantity * i.unit_price - COALESCE(i.discount, 0)) FILTER (WHERE DATE_TRUNC('month', o.order_date) = DATE_TRUNC('month', NOW())), 0) AS ca_in_progress_month
  FROM orders o JOIN order_items i ON i.order_id = o.id
  WHERE o.state IN ('paid', 'shipped', 'delivered')
  GROUP BY o.shipping_country
)
ORDER BY shipping_country;

-- Défi 19
SELECT COUNT(*) AS nb_clients,
  ROUND(100.0 * COUNT(*) FILTER (WHERE next_order_date <= order_date + INTERVAL '30 days') / COUNT(*), 2) AS pct_30_days,
  ROUND(100.0 * COUNT(*) FILTER (WHERE next_order_date <= order_date + INTERVAL '60 days') / COUNT(*), 2) AS pct_60_days,
  ROUND(100.0 * COUNT(*) FILTER (WHERE next_order_date <= order_date + INTERVAL '90 days') / COUNT(*), 2) AS pct_90_days
FROM (
  SELECT DISTINCT ON (user_id) order_date,
    LEAD(order_date) OVER (PARTITION BY user_id ORDER BY order_date) AS next_order_date
  FROM orders
  WHERE user_id IS NOT NULL AND state IN ('paid', 'shipped', 'delivered')
  ORDER BY user_id, order_date
);

-- Défi 20
SELECT a.variant_id AS variant_1, b.variant_id AS variant_2, COUNT(*) AS nb_orders
FROM order_items a
  JOIN order_items b ON b.order_id = a.order_id AND b.variant_id > a.variant_id
  JOIN orders o ON o.id = a.order_id
WHERE o.state IN ('paid', 'shipped', 'delivered')
GROUP BY a.variant_id, b.variant_id
ORDER BY nb_orders DESC
FETCH FIRST 10 ROWS WITH TIES;
