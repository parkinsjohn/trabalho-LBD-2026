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
