# CARSHARE

Данная база данных представляет собой систему внесения, хранения и удаления данных в сфере деятельности автопарка.
База данных приведена к форме 3NF, состоит из пяти таблиц.
Также база данных оснащена функциями, триггерами, которые служат для обеспечения эффективности функционала данной системы.

# К примеру триггерная функция, высчитывающая счет за услугу аренды определенного автомобиля исходя из его свойств:

CREATE FUNCTION public.trigger_bill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
if tg_op='INSERT' then
if (select client_id from val_clients where client_id=new.client_id)=new.client_id then
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2000 and 2005 then 
update inuse set bill = (select share_cost * 1.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id) between 2005 and 2015 then 
update inuse set bill = (select share_cost * 2.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2015 and 2023 then 
update inuse set bill = (select share_cost * 3.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;

else
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2000 and 2005 then 
update inuse set bill = (select share_cost * 1.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id) between 2005 and 2015 then 
update inuse set bill = (select share_cost * 2.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2015 and 2023 then 
update inuse set bill = (select share_cost * 3.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
end if;
end if;
return new;
end;
$$;

