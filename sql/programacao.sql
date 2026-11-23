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

--PROCEDURES
--===============================================================================
-- (e) C confirma uma escalação: verifica se ela tem exatamente a quantidade de 
-- cada posição exigida pelo esquema, exatamente um capitão entre os 11 atletas
-- e preço total dentro do patrimônio, e só então a marca como confirmada.       
--===============================================================================
CREATE OR REPLACE PROCEDURE fantasy_game.sp_confirmar_escalacao(
	p_id_escalacao integer
)
LANGUAGE plpgsql
AS $$
DECLARE
	v_esc fantasy_game.escalacao%ROWTYPE;
	v_estado text;
	v_esq fantasy_game.esquema_tatico%ROWTYPE;
	v_patrimonio fantasy_game.tecnico.patrimonio%TYPE;
	v_custo_total numeric(12, 2) := 0.00;
	v_qtd_capitaes integer := 0;
	v_cap_eh_tecnico boolean := false;
	v_gol smallint := 0;
	v_lat smallint := 0;
	v_zag smallint := 0;
	v_mei smallint := 0;
	v_ata smallint := 0;
	v_tec smallint := 0;
BEGIN
	SELECT * 
	  INTO v_esc
	  FROM fantasy_game.escalacao
	 WHERE id_escalacao = p_id_escalacao;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Escalacao % nao encontrada.', p_id_escalacao;
	END IF;

	IF COALESCE(v_esc.confirmada, false) IS TRUE THEN
		RAISE EXCEPTION 'Escalacao % ja esta confirmada ', p_id_escalacao;
	END IF;
	
	SELECT trim(estado)
	  INTO v_estado
	  FROM fantasy_game.estado
	 WHERE numero_rodada = v_esc.numero_rodada;

	IF NOT FOUND OR v_estado IS DISTINCT FROM 'aberta' THEN
	   RAISE EXCEPTION 'So e possivel confirmar escalacao em rodada com estado aberta.';
	END IF;

	SELECT * 
	  INTO v_esc
	  FROM fantasy_game.esquema_tatico
	 WHERE id_esquema = v_esc_id_esquema;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Esquema tatico % nao encontrado. ', v_esc.id_esquema;
	END IF;

	SELECT
		COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('GOL', 'G') THEN 1 ELSE 0 END), 0)::smallint,
	 	COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('LAT', 'L') THEN 1 ELSE 0 END), 0)::smallint,
		COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('ZAG', 'Z') THEN 1 ELSE 0 END), 0)::smallint, 
		COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('MEI', 'M') THEN 1 ELSE 0 END), 0)::smallint,
		COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('ATA', 'A') THEN 1 ELSE 0 END), 0)::smallint,
		COALESCE(SUM(CASE WHEN upper(trim(pos.abreviacao)) IN ('TEC', 'T') THEN 1 ELSE 0 END), 0)::smallint,
		COALESCE(bool_or(COALESCE(ea.eh_capitao, false) AND upper(trim(pos.abreviacao)) IN ('TEC', 'T')), false),
		COALESCE(SUM(ea.preco_pago), 0.00)::numeric(12, 2)
	  INTO v_gol, v_lat, v_zag, v_mei, v_lat, v_tec,
	  	   v_qtd_capitaes, v_cap_eh_tecnico, v_custo_total
	  FROM fantasy_game.escala_atleta ea
	  JOIN fantasy_game.atletas atl
	  	ON atl.id_atleta = ea.id_atleta
	  JOIN fantasy_game.posicao pos
	  	ON pos.id_posicao = atl.id_posicao
	 WHERE ea.id_escalacao = p_id_escalacao;

	IF v_gol <> COALESCE(v_esq.qtd_gol, 0)
	   OR v_lat <> COALESCE(v_esq.qtd_lat, 0)
	   OR v_zag <> COALESCE(v_esq.qtd_zag, 0)
	   OR v_mei <> COALESCE(v_esq.qtd_mei, 0)
	   OR v_ata <> COALESCE(v_esq.qtd_ata, 0)
	   OR v_tec <> COALESCE(v_esq.qtd_tec, 0) THEN

	    RAISE EXCEPTION 'Escalacao incompleta ou incorreta para o esquema %. ', v_esq.nome;
	END IF;

	IF v_qtd_capitaes <> 1 THEN 
		RAISE EXCEPTION 'A escalacao deve ter exatamente 1 capitao (encontrados: %).', v_qtd_capitaes;
	END IF;

	IF v_cap_eh_tecnico IS TRUE THEN 
		RAISE EXCEPTION 'O tecnico real nao pode ser escolhido como capitao. ';	
	END IF;

	SELECT patrimonio
	  INTO v_patrimonio
	  FROM fantasy_game.tecnico
	 WHERE id_tecnico = v_esc.id_tecnico;

	IF NOT FOUND OR v_patrimonio IS NULL OR v_custo_total > v_patrimonio THEN
	   RAISE EXCEPTION 'Custo total (%) ultrapasse o patrimonio do tecnico (%).	',
	   	  v_custo_total, v_patrimonio;
	END IF;

	UPDATE fantasy_game.escalcao
	   SET confirmada = true,
	   	   data_confirmacao = CURRENT_TIMESTAMP
	 WHERE id_escalacao = p_id_escalacao;
END;
$$;

--==========================================================================
--(f) Um procedimento que faz um técnico entrar em uma liga, verificando
-- o código de convite (para ligas privadas), o limite de participantes 
-- e se ele já participa
--==========================================================================
CREATE OR REPLACE PROCEDURE fantasy_game.sp_entrar_liga(
	p_id_liga integer,
	p_id_tecnico integer,
	p_codigo_convite text DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
		v_liga fantasy_game.liga%ROWTYPE;
		v_qtd_atual integer := 0;
BEGIN
	SELECT * 
	  INTO v_liga
	  FROM fantasy_game.liga
	 WHERE id_liga = p_id_liga;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Liga % nao encontrada. ', p_id_liga;
	END IF;

	PERFORM 1
	   FROM fantasy_game.tecnico
	  WHERE id_tecnico = p_id_tecnico;
	  
	IF NOT FOUND THEN
		RAISE EXCEPTION 'Tecnico % nao encontrado. ', p_id_tecnico;
	END IF;

	PERFORM 1
	   FROM fantasy_game.particpa
	  WHERE id_liga = p_id_liga
	  	AND id_tecnico = p_id_tecnico;
	  
	IF NOT FOUND THEN
		RAISE EXCEPTION 'O tecnico % ja particpa da liga %. ', p_id_tecnico, p_id_liga;
	END IF;

	IF COALESCE(v_liga.publica, true) IS FALSE THEN
		IF p_codigo_convite IS NULL
		   OR trim(p_codigo_convite) IS DISTINCT FROM trim(COALESCE(v_liga.codigo_convite, '')) THEN
			RAISE EXCEPTION 'Codigo de convite invalido para entrar na liga privada.';
		END IF;
	END IF;

	IF v_liga.limite_partipantes IS NOT NULL THEN
		SELECT COUNT(*)::integer
		  INTO v_qtd_atual
	 	  FROM fantasy_game.participa
		 WHERE id_liga = p_id_liga;

	    IF v_qtd_atual >= v_liga.limite_participantes THEN
			RAISE EXCEPTION 'A liga % atingiu maximo de % participantes.',
				p_id_liga, v_liga.limite_participantes;
		END IF;
	END IF;

	INSERT INTO fantasy_game.participa (id_liga, id_tecnico, data_entrada)
	VALUES (p_id_liga, p_id_tecnico, CURRENT_DATE);
END;
$$;

--=======================================================================================
--(G)Um procedimento que consolida uma rodada fechada, numa única transação: calcula as
-- pontuações, aplica a valorização dos atletas
-- e grava o histórico de preços, atualiza o patrimônio dos técnicos e marca a rodada como 
-- consolidada. Se qualquer passo falhar, nada pode ficar gravado pela metade. O procedimento 
-- não pode ser executado duas vezes para a mesma rodada nem para uma rodada que não 
--esteja fechada.
