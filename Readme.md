## Personne

- Roland HUON

## Défi SQL 01

"Quel est le montant moyen d'une commande validée dans chaque pays de livraison ? Comparez le nombre de commandes et le chiffre d'affaires."

### Code SQL :

```sql
select o.shipping_country,
       count(distinct o.id) as nb_commandes,
       sum(i.quantity * i.unit_price - coalesce(i.discount, 0)) as chiffre_affaires,
       round(sum(i.quantity * i.unit_price - coalesce(i.discount, 0)) / count(distinct o.id), 2) as montant_moyen
from orders o
join order_items i on i.order_id = o.id
where o.state in ('paid', 'shipped', 'delivered')
group by o.shipping_country
order by chiffre_affaires desc;
```

### Résultat :

| shipping_country | nb_commandes | chiffre_affaires | montant_moyen |
|---|---|---|---|
| FR | 1528 | 696165.42 | 455.61 |
| CH | 185 | 92327.10 | 499.07 |
| BE | 145 | 64847.51 | 447.22 |