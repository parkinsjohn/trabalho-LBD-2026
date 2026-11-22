--(a) Calcula a pontuação de um atleta em uma rodada a partir dos seus scouts, 
--respeitando as observações por posição (via tabela pontua_para)
-- Se não entrou em campo na rodada, retorna 0,00.

CREATE OR REPLACE FUNCTION fantasy_game.fn_pontuacao_atleta_rodada(
	p_id_atleta integer,
	p_numero_partida integer
)
RETURNS numeric(8, 2)
LANGUAGE plpgsql
AS $$
DECLARE
	v_entrou boolean;
	v_pontos numeric(8, 2);
BEGIN
	SELECT COALESCE(bool_or(a.entrou_em_campo), false)
	  INTO v_entrou
	  FROM fanatsy_game.atua a
	  JOIN fantasy_.partida p
	    ON p.indicacao_partida = a.indicacao_partida
	 WHERE a.id_atleta = p_id_atleta
	   AND p.numero_rodada = p_numero_rodada;

	IF NOT COALESCE(v_entroy, false) THEN 
		RETURN 0.00;
	END IF;

	SELECT COALESCE(SUM(gs.quantidade::numeric * ts.valor_pontos), 0.00)::numeric(8, 2)
	  INTO v_pontos
	  FROM fantasy_game.gera_scout gs
	  JOIN fantasy_game.partida p
	  	ON p.indicacao_partida = gs.indicao_partida
	  JOIN fantasy_game.atletas atl
	  	ON atl.id_atleta = gs.id_atleta
	  JOIN fantasy_game.tipo_scout ts
	  	ON trim(ts.sigla) = trim(gs.sigla)
	  JOIN fantasy_game.pontua_para pp
	    ON trim(pp.sigla) = trim(gs.sigla)
	   AND pp.id_posicao = atl.id_posicao
	 WHERE gs.id_atleta = p_id_atleta
	   AND p.numero_rodada = p_numero_rodada;
	
	RETURN COALESCE(v_pontos, 0.00);
END;
$$;


-- (b)calcula a pontuação de uma escalação na rodada: 
-- soma os 11 atletas (capitão * 1.5) + pontuação do técnico real (5 vitoria, 2 empates, 0 derrota/não jogou)
CREATE OR REPLACE FUNCTION fantasy_game.fn_pontuacao_escalacao(
	p_id_escalacao integer
)
RETURNS numeric(8, 2)
LANGUAGE plpgsql
AS $$
DECLARE
	v_rodada integer;
	v_pontos_atletas numeric(8, 2) := 0.00;
	v_pontos_tecnico_real numeric(8, 2) := 0.00;
BEGIN
	SELECT esc.numero_rodada
	  INTO v_rodada
	  FROM fantasy_game.escalacao esc
	WHERE esc.id_escalacao = p_id_escalacao;

   IF v_rodada IS NULL THEN
	   RETURN 0.00;
   END IF;

   -- Pontuacao dos atletas de campo/goleiro escalados (capitao com multiplicador 1.5)
   SELECT COALESCE(
   			  SUM(COALESCE(at.potuacao_rodada,fantasy_game.fn_pontuacao_atleta_rodada(ea.id_atleta, v_rodada))
				  * CASE WHEN COALESCE(ea.eh_capitao, false) 
				  		  AND upper(trim(pos.abreviacao)) NOT IN ('TEC', 'T')
						 THEN 1.50
						 ELSE 1.00 
					END
			  ),
			  0.00
		  )::numeric(8, 2)
	 INTO v_pontos_atletas
	 FROM fantasy_game.escala_atleta ea
	 JOIN fantasy_game.atletas atl
	   ON atl.id_atleta = ea.id_atleta
	 JOIN fantasy_game.posicao pos
	   ON pos.id_posicao = atl.id_posicao
	 LEFT JOIN fantasy_game.atua at
	   ON at.id_atlata = ea.id_atleta
	  AND at.indicacao_partida IN (
		  SELECT p.indicacao_partida 
		  	FROM fantasy_game.partida p
		  WHERE p.numero_rodada = v_rodada
	  )
	WHERE ea.id_escalacao = p_id_escalacao
	  AND upper(trim(pos.anrevicao)) NOT IN ('TEC', 'T');

	-- Pontuação de técnico real escalado na rodada (5 vitória, 2 empates, 0 derrota/não jogou)
	SELECT COALESCE(
				SUM(
					CASE
						WHEN p.indicacao_partida IS NULL THEN 0.00
						WHEN p.id_clube_mandante = pert.id_clube AND p.placar_mandante > p.placar_visitante THEN 5.00
						WHEN p.id_clube_visitante = pert.id_clube AND p.placar_visitante > p.placar_mandante THEN 5.00
						WHEN (p.id_clube_mandante =  pert.id_clube OR p.id_clube_visitante = pert.id_clube)
							 AND p.placar_mandante = p.placar_visitante THEN 2.00
						ELSE 0.00
					END
				),
				0.00
	        )::numeric(8, 2)
	   INTO v_pontos_tecnico_real
	   FROM fantasy_game.escala_atleta ea
	   JOIN fantasy_game.atletas atl
	   	 ON atl.id_atleta = ea.id_atleta
	   JOIN fantasy_game.posicao pos
	   	 ON pos.id_posicao = atl.id_posicao
       LEFT JOIN fantasy_game.pertence pert
   	     ON pert.id_atleta = ea.id_atleta
		AND pert.numero_rodada = v_rodada
	   LEFT JOIN fantasy_game.partida p
	   	 ON p.numero_rodada = v_rodada
		AND (p.id_clube_mandante = pert.id_clube OR p.id_clube_visitante = pert.id_clube)
	  WHERE ea.id_escalacao = p_id_escalacao
	  	AND upper(trim(pos.abreviacao)) IN ('TEC', 'T');

	 RETURN (v_pontos_atleats + v_pontos_tecnico_real)::numeric(8, 2);
END;
$$;
