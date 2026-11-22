-- The catalogue search compared every typed word with every word of every food (name, brand, nine translations,
-- aliases) through a helper that normalized both words again and ran one query per joined-word pair: 3-9 s per
-- search on 1,385 foods. Same rules, same results (checked on 17 searches against production), about ten times faster.

-- Same matching rules as food_search_token_matches, for tokens that are already normalized: no regex work and no
-- per-call settings, so Postgres can run it inline.
create or replace function public.food_search_normalized_token_matches(p_query_token text, p_candidate_token text)
returns boolean
language sql
immutable parallel safe
as $$
  select case
    when p_query_token = '' or p_candidate_token = '' then false
    when p_query_token = p_candidate_token then true
    when length(p_query_token) >= 3 and length(p_candidate_token) >= 3
      and p_candidate_token like p_query_token || '%' then true
    when length(p_query_token) >= 3 and length(p_candidate_token) >= 3
      and p_query_token like p_candidate_token || '%'
      and length(p_query_token) - length(p_candidate_token) <= 2 then true
    when length(p_query_token) < 4 or length(p_candidate_token) < 4
      or left(p_query_token, 1) <> left(p_candidate_token, 1) then false
    else extensions.levenshtein_less_equal(p_query_token, p_candidate_token,
           case when length(p_query_token) >= 9 or length(p_query_token) between 5 and 6 then 2 else 1 end)
         <= case when length(p_query_token) >= 9 or length(p_query_token) between 5 and 6 then 2 else 1 end
      and 1 - extensions.levenshtein_less_equal(p_query_token, p_candidate_token,
           case when length(p_query_token) >= 9 or length(p_query_token) between 5 and 6 then 2 else 1 end)::numeric
           / greatest(length(p_query_token), length(p_candidate_token))
         >= case when length(p_query_token) >= 5 then 0.66 else 0.74 end
  end
$$;

-- Same rules as before. The candidate is normalized once per call instead of once per comparison, and joined words
-- are built from the token array instead of one query per pair; normalizing a joined or plural form can only change
-- it through the two one-word spelling fixes, which are applied to those forms directly.
create or replace function public.food_search_query_token_matches_candidate(p_query_token text, p_candidate text)
returns boolean
language plpgsql
immutable parallel safe
set search_path to 'public', 'extensions'
as $function$
declare
  query_token text := public.food_search_normalize(p_query_token);
  candidate_tokens text[] := regexp_split_to_array(public.food_search_normalize(p_candidate), '\s+');
  candidate_count integer := coalesce(array_length(candidate_tokens, 1), 0);
  candidate_index integer;
  token text;
begin
  if candidate_count = 0 or query_token = '' then return false; end if;
  for candidate_index in 1..candidate_count loop
    token := candidate_tokens[candidate_index];
    if public.food_search_normalized_token_matches(query_token, token) then return true; end if;
    if right(token, 3) = 'ies' and public.food_search_normalized_token_matches(query_token,
         replace(replace(left(token, length(token) - 3) || 'y', 'omlette', 'omelette'), 'raviolli', 'ravioli')) then
      return true;
    end if;
    if right(token, 3) = 'oes' and public.food_search_normalized_token_matches(query_token,
         replace(replace(left(token, length(token) - 2), 'omlette', 'omelette'), 'raviolli', 'ravioli')) then
      return true;
    end if;
    if right(token, 1) = 'o' and public.food_search_normalized_token_matches(query_token,
         replace(replace(token || 'es', 'omlette', 'omelette'), 'raviolli', 'ravioli')) then
      return true;
    end if;
    if candidate_index + 1 <= candidate_count and public.food_search_normalized_token_matches(query_token,
         replace(replace(token || candidate_tokens[candidate_index + 1], 'omlette', 'omelette'), 'raviolli', 'ravioli')) then
      return true;
    end if;
    if candidate_index + 2 <= candidate_count and public.food_search_normalized_token_matches(query_token,
         replace(replace(token || candidate_tokens[candidate_index + 1] || candidate_tokens[candidate_index + 2],
           'omlette', 'omelette'), 'raviolli', 'ravioli')) then
      return true;
    end if;
  end loop;
  return false;
end;
$function$;
