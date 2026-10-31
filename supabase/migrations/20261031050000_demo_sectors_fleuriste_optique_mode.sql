-- MOD-057 : trois nouveaux secteurs de démo (fleuriste, opticien, hoodies), construits par manager_build_demo.
-- Images Unsplash (licence Unsplash), logos dans public/demo/.
insert into public.demo_sectors (key, label, brand, category, sort, promos, own_promos) values
('fleuriste', 'Fleuriste', 'Pétale & Tige', 'fleuriste', 3,
 '[
  {"title":"Bouquet de saison","mech":"-20 %","type":"percent","val":20,"orig":39,"desc":"Notre bouquet de saison composé chaque matin, -20 % toute la semaine.","code":"SAISON20","img":"1523308458373-c6f61ae1fd21","start":-3,"days":12},
  {"title":"Roses par 10","mech":"19,90 € au lieu de 29,90 €","type":"new_price","val":19.9,"orig":29.9,"desc":"Dix roses de France, longues tiges, emballage offert.","code":"ROSES10","img":"1620752379460-d4adfe02a5ce","start":-5,"days":15},
  {"title":"Compositions de table","mech":"-15 %","type":"percent","val":15,"orig":45,"desc":"Centres de table pour vos dîners et fêtes, sur commande 48 h avant.","code":"TABLE15","img":"1530488228536-37ae1dbb20a4","start":-2,"days":20},
  {"title":"Bouquet acheté, vase offert","mech":"Vase offert dès 40 € d''achat","type":"free_with_condition","desc":"Pour tout bouquet dès 40 €, le vase en verre est offert.","code":"VASE","img":"1558879787-4c4aea1fbb83","start":-1,"days":10,"mand":true},
  {"title":"Fleurs de la Toussaint","mech":"2 achetées, la 3e offerte","type":"x_plus_y","desc":"Compositions et plantes pour la Toussaint : la troisième est offerte.","code":"TOUSSAINT3","img":"1587317997367-3d47566f9528","start":-8,"days":10},
  {"title":"Abonnement fleurs","mech":"-25 %","type":"percent","val":25,"desc":"Un bouquet livré chaque semaine, -25 % les deux premiers mois.","code":"ABO25","img":"1564070814872-a2e801dbf413","start":3,"days":20}
 ]',
 '[
  {"title":"Atelier bouquet du samedi","mech":"Atelier offert samedi","type":"free_with_condition","desc":"Composez votre bouquet avec notre fleuriste, samedi de 10 h à 12 h. Sur inscription en magasin.","img":"1604137488398-b1d691713d96","start":-1,"days":7},
  {"title":"Pivoines et renoncules","mech":"-10 %","type":"percent","val":10,"desc":"Arrivage du jour : pivoines et renoncules à -10 %.","code":"PIVOINE","img":"1610190427750-03e9095f18e3","start":-2,"days":8}
 ]'),
('optique', 'Opticien', 'Lunetterie Lumière', 'optique', 4,
 '[
  {"title":"Deuxième paire offerte","mech":"2e paire offerte","type":"free_with_condition","desc":"Pour l''achat d''une paire de lunettes de vue, la deuxième paire est offerte (verres unifocaux).","code":"PAIRE2","img":"1486250944723-86bca2b15b06","start":-6,"days":30,"mand":true},
  {"title":"Montures de créateurs","mech":"-30 %","type":"percent","val":30,"orig":220,"desc":"Notre sélection de montures de créateurs à -30 %.","code":"CREA30","img":"1758552322632-ba288778c770","start":-3,"days":14},
  {"title":"Solaires à votre vue","mech":"-20 %","type":"percent","val":20,"orig":180,"desc":"Lunettes de soleil avec verres correcteurs à -20 %.","code":"SOLEIL20","img":"1776890948428-5cb3e62cc680","start":-2,"days":21},
  {"title":"Examen de vue offert","mech":"Examen offert","type":"free_with_condition","desc":"Contrôle de la vue gratuit en magasin, sans rendez-vous.","img":"1517948430535-1e2469d314fe","start":-10,"days":40},
  {"title":"Verres anti-lumière bleue","mech":"49 € au lieu de 79 €","type":"new_price","val":49,"orig":79,"desc":"Le traitement anti-lumière bleue pour vos écrans, sur verres neufs.","code":"BLEU49","img":"1574258495973-f010dfbb5371","start":-4,"days":18},
  {"title":"Lentilles : 3 boîtes achetées","mech":"3 achetées, la 4e offerte","type":"x_plus_y","desc":"Lentilles mensuelles : la quatrième boîte est offerte.","code":"LENT4","img":"1534078477103-9f6a18b3a5e2","start":4,"days":15}
 ]',
 '[
  {"title":"Ajustage et nettoyage offerts","mech":"Entretien offert","type":"free_with_condition","desc":"Passez faire ajuster et nettoyer vos lunettes, même achetées ailleurs.","img":"1591076482161-42ce6da69f67","start":-1,"days":14},
  {"title":"Montures vintage","mech":"-15 %","type":"percent","val":15,"desc":"Arrivage de montures vintage restaurées, -15 % cette semaine.","code":"VINTAGE","img":"1759910546772-73e4bb7fdadd","start":-2,"days":9}
 ]'),
('mode', 'Mode · hoodies', 'Hoodie Club', 'mode', 5,
 '[
  {"title":"Hoodies oversize","mech":"-25 %","type":"percent","val":25,"orig":69,"desc":"Toute la collection oversize à -25 % : coton bio, coupe ample.","code":"OVER25","img":"1556821840-3a63f95609a7","start":-4,"days":14},
  {"title":"2 hoodies achetés, le 3e offert","mech":"2 achetés, le 3e offert","type":"x_plus_y","desc":"Composez votre lot : le troisième hoodie est offert.","code":"HOOD3","img":"1499971856191-1a420a42b498","start":-2,"days":12,"mand":true},
  {"title":"Hoodie blanc essentiel","mech":"39 € au lieu de 59 €","type":"new_price","val":39,"orig":59,"desc":"Le hoodie blanc qu''on porte avec tout, en édition limitée.","code":"BLANC39","img":"1615397587950-3cbb55f95b77","start":-6,"days":20},
  {"title":"Sweats colorés","mech":"-20 %","type":"percent","val":20,"orig":55,"desc":"Jaune, orange, violet : nos sweats couleur à -20 %.","code":"COULEUR20","img":"1578587018452-892bacefd3f2","start":-1,"days":10},
  {"title":"Collection streetwear","mech":"-15 %","type":"percent","val":15,"desc":"Hoodies imprimés et vestes de la nouvelle collection.","code":"STREET15","img":"1680292783974-a9a336c10366","start":-3,"days":16},
  {"title":"Black Friday Hoodie Club","mech":"-30 %","type":"percent","val":30,"desc":"Quatre jours de prix fous sur tout le magasin.","code":"BLACK30","img":"1564557287817-3785e38ec1f5","start":27,"days":4}
 ]',
 '[
  {"title":"Personnalisation offerte","mech":"Broderie offerte dès 60 €","type":"free_with_condition","desc":"Faites broder vos initiales sur votre hoodie, offert dès 60 € d''achat.","img":"1601063476271-a159c71ab0b3","start":-1,"days":10},
  {"title":"Hoodies femme","mech":"-20 %","type":"percent","val":20,"desc":"La collection femme à -20 % : coupes courtes et couleurs pastel.","code":"FEMME20","img":"1565693413579-8ff3fdc1b03b","start":-2,"days":12}
 ]')
on conflict (key) do update set label = excluded.label, brand = excluded.brand, category = excluded.category,
  promos = excluded.promos, own_promos = excluded.own_promos, sort = excluded.sort;
