-- foods and logged_food_entries carry CHECK constraints that call this validator. A CHECK runs
-- as the writing role, so without EXECUTE every direct food save by a signed-in person is refused.
grant execute on function public.apex_valid_nutrient_evidence(jsonb) to authenticated;
