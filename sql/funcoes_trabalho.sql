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

-- ============================================================
-- ITEM C - VALIDACAO DA ESCALACAO
-- ============================================================
CREATE OR REPLACE FUNCTION fantasy_game.validar_escalacao()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado TEXT;
    v_confirmada BOOLEAN;
    v_situacao TEXT;
    v_patrimonio NUMERIC(10,2);
    v_total NUMERIC(12,2);
BEGIN
    -- Em UPDATE ou DELETE, valida tambem a escalacao de origem.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT es.confirmada, est.estado
          INTO v_confirmada, v_estado
          FROM fantasy_game.escalacao es
          LEFT JOIN fantasy_game.estado est
            ON est.numero_rodada = es.numero_rodada
         WHERE es.id_escalacao = OLD.id_escalacao;

        IF NOT FOUND OR v_estado IS DISTINCT FROM 'aberta' THEN
            RAISE EXCEPTION
                'Nao e permitido alterar atletas: a rodada da escalacao nao esta aberta.';
        END IF;

        IF v_confirmada IS TRUE THEN
            RAISE EXCEPTION
                'Nao e permitido alterar atletas: a escalacao ja foi confirmada.';
        END IF;
    END IF;

    -- Em INSERT ou UPDATE, valida a escalacao de destino.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT es.confirmada, est.estado, tec.patrimonio
          INTO v_confirmada, v_estado, v_patrimonio
          FROM fantasy_game.escalacao es
          LEFT JOIN fantasy_game.estado est
            ON est.numero_rodada = es.numero_rodada
          LEFT JOIN fantasy_game.tecnico tec
            ON tec.id_tecnico = es.id_tecnico
         WHERE es.id_escalacao = NEW.id_escalacao;

        IF NOT FOUND OR v_estado IS DISTINCT FROM 'aberta' THEN
            RAISE EXCEPTION
                'Nao e permitido alterar atletas: a rodada da escalacao nao esta aberta.';
        END IF;

        IF v_confirmada IS TRUE THEN
            RAISE EXCEPTION
                'Nao e permitido alterar atletas: a escalacao ja foi confirmada.';
        END IF;

        -- Somente atletas em situacao provavel ou duvida podem ser escalados.
        SELECT sit.nome
          INTO v_situacao
          FROM fantasy_game.atletas at
          LEFT JOIN fantasy_game.situacao sit
            ON sit.id_situacao = at.id_situacao
         WHERE at.id_atleta = NEW.id_atleta;

        IF NOT FOUND OR v_situacao IS NULL
           OR lower(trim(v_situacao)) NOT IN ('provavel', 'dúvida', 'duvida') THEN
            RAISE EXCEPTION
                'Atleta nao pode ser escalado: somente atletas provaveis ou em duvida sao permitidos.';
        END IF;

        -- Soma os precos ja registrados na escalacao.
        -- Em UPDATE, desconsidera a linha antiga quando ela pertence
        -- a mesma escalacao que esta sendo alterada.
        SELECT COALESCE(SUM(ea.preco_pago), 0)
          INTO v_total
          FROM fantasy_game.escala_atleta ea
         WHERE ea.id_escalacao = NEW.id_escalacao
           AND NOT (
               TG_OP = 'UPDATE'
               AND OLD.id_escalacao = NEW.id_escalacao
               AND ea.id_atleta = OLD.id_atleta
           );

        v_total := v_total + COALESCE(NEW.preco_pago, 0);

        IF v_patrimonio IS NULL OR v_total > v_patrimonio THEN
            RAISE EXCEPTION
                'Patrimonio insuficiente. Preco total: %, patrimonio do tecnico: %.',
                v_total, v_patrimonio;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_escalacao
    ON fantasy_game.escala_atleta;

CREATE TRIGGER trg_validar_escalacao
BEFORE INSERT OR UPDATE OR DELETE
ON fantasy_game.escala_atleta
FOR EACH ROW
EXECUTE FUNCTION fantasy_game.validar_escalacao();


-- ============================================================
-- ITEM D - ATUALIZACAO DA PONTUACAO DOS ATLETAS
-- ============================================================

CREATE OR REPLACE FUNCTION fantasy_game.atualizar_pontuacao_scout()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_atleta INTEGER;
    v_indicacao_partida INTEGER;
BEGIN
    -- Se o scout antigo foi removido ou alterado, recalcula
    -- a pontuacao do atleta na partida antiga.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_id_atleta := OLD.id_atleta;
        v_indicacao_partida := OLD.indicao_partida;

        UPDATE fantasy_game.atua at
           SET pontuacao_rodada = COALESCE((
               SELECT SUM(gs.quantidade * ts.valor_pontos)
                 FROM fantasy_game.gera_scout gs
                 JOIN fantasy_game.tipo_scout ts
                   ON ts.sigla = gs.sigla
                 JOIN fantasy_game.atletas atl
                   ON atl.id_atleta = gs.id_atleta
                 JOIN fantasy_game.pontua_para pp
                   ON pp.sigla = gs.sigla
                  AND pp.id_posicao = atl.id_posicao
                WHERE gs.id_atleta = v_id_atleta
                  AND gs.indicacao_partida = v_indicacao_partida
           ), 0)
         WHERE at.id_atleta = v_id_atleta
           AND at.indicacao_partida = v_indicacao_partida;
    END IF;

    -- Se o scout foi inserido ou alterado, recalcula
    -- a pontuacao do atleta na partida nova.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_id_atleta := NEW.id_atleta;
        v_indicacao_partida := NEW.indicacao_partida;

        UPDATE fantasy_game.atua at
           SET pontuacao_rodada = COALESCE((
               SELECT SUM(gs.quantidade * ts.valor_pontos)
                 FROM fantasy_game.gera_scout gs
                 JOIN fantasy_game.tipo_scout ts
                   ON ts.sigla = gs.sigla
                 JOIN fantasy_game.atletas atl
                   ON atl.id_atleta = gs.id_atleta
                 JOIN fantasy_game.pontua_para pp
                   ON pp.sigla = gs.sigla
                  AND pp.id_posicao = atl.id_posicao
                WHERE gs.id_atleta = v_id_atleta
                  AND gs.indicacao_partida = v_indicacao_partida
           ), 0)
         WHERE at.id_atleta = v_id_atleta
           AND at.indicacao_partida = v_indicacao_partida;
    END IF;

    -- Trigger AFTER: o valor retornado e ignorado.
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_atualizar_scout
    ON fantasy_game.gera_scout;

CREATE TRIGGER trg_atualizar_scout
AFTER INSERT OR UPDATE OR DELETE
ON fantasy_game.gera_scout
FOR EACH ROW
EXECUTE FUNCTION fantasy_game.atualizar_pontuacao_scout();
