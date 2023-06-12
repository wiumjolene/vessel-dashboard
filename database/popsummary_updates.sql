DELIMITER $$
CREATE DEFINER=`agrihub`@`%` PROCEDURE `popsummarytable_saildate20230508`()
BEGIN
  -- declare local variables
 -- declare local variables
   Declare lComm char(2);
   Declare lseason char(4);
   Declare lstart_date, lend_date datetime;
   Declare luse_airfreight_tbl  char(1);
   Declare linclude_airfreight  char(1);
   DECLARE done INT DEFAULT FALSE;


   DECLARE commoditylist CURSOR
   FOR
     SELECT commodity, start_date,End_date, Season , Use_Airfreight_tbl, Include_Airfreight
     FROM Report_seasons a, (SELECT DISTINCT reportcomm FROM dim_variety) AS b
     WHERE  Start_date <= CURDATE() AND End_date >= CURDATE()
     AND a.Commodity = b.reportcomm;

   #declare handle 
   DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
  --  DECLARE CONTINUE HANDLER FOR SQLSTATE '02000' SET done = 1;

   OPEN commoditylist;

   Fetch commoditylist into lComm, lstart_date, lend_date,lseason,luse_airfreight_tbl,linclude_airfreight  ;

 --  select lComm , lstart_date, lend_date,lseason ,luse_airfreight_tbl,linclude_airfreight, now();

    while  done = FALSE do
    --  select lComm , lstart_date, lend_date,lseason;

    -- delete existing data.
      DELETE FROM SummaryTableTest20230508 
      WHERE (commodity = lComm and seasons = lseason)
      OR (seasons is NULL);

  if lComm = 'DR' 
  then

       INSERT INTO SummaryTableTest20230508 (commodity, id_variety, shipped_week, iso_port, port_country, port_region, exporter_region,
          var_grp, comm_grp, act_ctns, eqv_ctns, plt_qty, load_port, vesselname, id_port, seasons,mass, grade, voyage, transport, size_count,
          id_vessel, combo_region, shipped_month)
       SELECT b.Commodity, a.id_variety, 0, a.id_port, a.target_country, a.target_region, a.target_region, b.VarGrp, b.CommGroup, 0,0,0,a.load_port_derived,
          '_',a.id_port_derived, a.season, SUM(a.nett_mass),a.grade, '_',a.transport, a.size_count,a.id_vessel, a.target_region, a.month
       from data_raisins a, dim_variety b
       where a.id_variety = b.id_variety
       and b.Commodity =  lComm
       and a.season =  lseason
       group by b.Commodity, a.id_variety, a.id_port, a.target_country, a.target_region, a.target_region,
                 b.VarGrp, b.CommGroup, a.load_port_derived,'_',a.id_port_derived, a.season,a.transport, a.size_count,
                a.id_vessel, a.target_region, a.month

        ;
  else --  lComm ='DR' then


    -- insert new data

      INSERT INTO  SummaryTableTest20230508 (commodity, id_variety, shipped_week,
            shipped_week_za, shipped_week_pol, iso_port, port_country, 
            port_region, exporter_region, combo_region, comm_grp, load_port, 
            vesselname, id_port,seasons, grade,voyage, transport, size_count, 
            id_vessel, sail_date_id, act_ctns, eqv_ctns, plt_qty, mass)

        SELECT ReportComm as commodity,
        id_variety,
        /* PF and SF requested to view final vessel departures from ZA ports */
        IF(Commgroup in ('PF', 'SF'), t.week_season, t2.week_season) as shipped_week,
        t.week_season as shipped_week_za,
        t2.week_season as shipped_week_pol,
        ISO_port_code,
        country,
        PortRegion,
        TARGET_REGION_VALID,
        if (PortRegion = 'UNK', TARGET_REGION_VALID, PortRegion) as combo_region,
        Commgroup,
        LoadPort,
        VesselName,
        ID_PORT_DERIVED,
        -- ItAll.season,
        IF(Commgroup in ('PF'), t.year, ItAll.season) as season,
        grade,
        OutboundVoyage,
        TRANSPORT,
        trim(size_count),
        id_vessel_derived,
        sail_date_id,
        sum(ctn_qty) AS cnt_qty,
        sum(EqvCartons) as EqvCartons,
        sum(plt_qty) AS Plt_qty,
        sum(Mass) as Mass
        from (
            SELECT straight_join h.ReportComm,
            g.id_variety,

            CASE WHEN z.shipped_date_confirmed = 1 THEN z.sail_date 
              WHEN z.shipped_date_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
            END as ship_date_pol,

            /* Use vessel zasail date from data_sail_date table where applicable */
            CASE WHEN z.zasaildate_confirmed = 1 THEN z.zasaildate 
              WHEN z.zasaildate_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
            END as ship_date_za,

            IF(z.zasaildate IS NOT NULL, z.zasaildate, '1900-01-01') as zasaildate,
            m.ISO_port_code,
            m.country,
            m.Region as PortRegion,
            g.TARGET_REGION_VALID,
            h.Commgroup,
            -- IF(z.load_port_assign IS NOT NULL, z.load_port_assign, g.LOAD_PORT_DERIVED) as LoadPort, -- 2022-02-08: update when vessels working is incorp
            g.LOAD_PORT_DERIVED as LoadPort,
            v.VesselName,
            g.ID_PORT_DERIVED,
            lseason as season,
            g.grade,
            q.OutboundVoyage,
            g.TRANSPORT,
            size_count,
            g.id_vessel_derived,
            z.sail_date_id,
            sum(ctn_qty) AS ctn_qty,
            sum(g.Mass) / k.MASS as EqvCartons,
            -- sum(plt_qty) AS Plt_qty,
            count(DISTINCT g.SSCC) AS Plt_qty,
            sum(g.Mass) as Mass
            FROM (
                SELECT DISTINCT ReportComm,
                Commgroup,
                MixedInd,
                id_variety
                from dim_variety
                WHERE ReportComm = lComm
            ) AS h,
            mates g -- force INDEX (mates_id_var_ship_date_derive_active)
            LEFT JOIN (SELECT sd.sail_date_id, sd.id_vessel, load_port, load_port_assign, 
                      shipped_date_derived, pv.shipped_date as sail_date, pv.zasaildate, 
                      pv.shipped_date_confirmed, pv.zasaildate_confirmed 
                    FROM agrihub.vessels_port_shipped_date sd
                    LEFT JOIN agrihub.vessels_sail_date pv ON (sd.sail_date_id=pv.id)) z 
                ON (z.id_vessel=g.id_vessel_derived AND g.SHIP_DATE_DERIVED=z.shipped_date_derived AND g.LOAD_PORT_DERIVED=z.load_port)
            LEFT JOIN ContainerInfo q ON (g.AGRIHUB_REF = q.Agrihub_ref),
            Report_Comm_Weeks j,
            StdEqvWeight k,
            dim_vessels v,
            dim_iso_ports m
            left join ppecb_region_country p ON(m.country = p.country)
            WHERE Active = 'Y'
            AND REVISION <> '99'
            AND h.ReportComm = k.commodity
            AND h.ReportComm = lComm
            AND Ship_Weeks_DERIVED = j.week
            AND h.ReportComm = j.COMMODITY
            AND g.Country IN ('ZA', '  ')
            AND g.channel IN ('E', ' ')
            and g.TRANSPORT <> if (linclude_airfreight = 'Y','^', 'A')
            AND g.id_variety = h.id_variety
            and g.id_vessel_derived = v.id_vessel
            AND lstart_date <= g.SHIP_DATE_DERIVED
            AND g.SHIP_DATE_DERIVED <= lend_date
            AND g.ID_PORT_DERIVED = m.id_ports 
            GROUP BY h.ReportComm,
            g.id_variety,

            /* Use vessel sail date from data_sail_date table in case NAVIS is not working */
              CASE WHEN z.shipped_date_confirmed = 1 THEN z.sail_date 
              WHEN z.shipped_date_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
              END,

            /* Use vessel zasail date from data_sail_date table where applicable */
            CASE WHEN z.zasaildate_confirmed = 1 THEN z.zasaildate 
              WHEN z.zasaildate_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
              END,

            IF(z.zasaildate IS NOT NULL, z.zasaildate, '1900-01-01'),
            m.ISO_port_code,
            m.country,
            m.Region,
            g.TARGET_REGION_VALID,
            h.Commgroup,
            -- IF(z.load_port_assign IS NOT NULL, z.load_port_assign, g.LOAD_PORT_DERIVED) as LoadPort, -- 2022-02-08: update when vessels working is incorp
            g.LOAD_PORT_DERIVED,
            v.VesselName,
            g.ID_PORT_DERIVED,
            g.grade,
            q.OutboundVoyage,
            g.TRANSPORT,
            size_count,
            g.id_vessel_derived,
            z.sail_date_id

            UNION ALL

            SELECT straight_join h.ReportComm,
            g.id_variety,

            /* Use vessel sail date from data_sail_date table in case NAVIS is not working */
            CASE WHEN z.shipped_date_confirmed = 1 THEN z.sail_date 
              WHEN z.shipped_date_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
            END as ship_date_pol,

            /* Use vessel zasail date from data_sail_date table where applicable */
            CASE WHEN z.zasaildate_confirmed = 1 THEN z.zasaildate 
              WHEN z.zasaildate_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
            END as ship_date_za,

            IF(z.zasaildate IS NOT NULL, z.zasaildate, '1900-01-01') as zasaildate,
            m.ISO_port_code,
            m.country,
            m.Region as PortRegion,
            g.TARGET_REGION_VALID,
            h.Commgroup,
            -- IF(z.load_port_assign IS NOT NULL, z.load_port_assign, g.LOAD_PORT_DERIVED) as LoadPort, -- 2022-02-08: update when vessels working is incorp
            g.LOAD_PORT_DERIVED as LoadPort,
            v.VesselName,
            g.ID_PORT_DERIVED,
            lseason as season,
            g.grade,
            q.OutboundVoyage,
            g.TRANSPORT,
            size_count,
            g.id_vessel_derived,
            z.sail_date_id,
            sum(ctn_qty) AS ctn_qty,
            sum(g.Mass) / k.MASS as EqvCartons,
            -- sum(plt_qty) AS Plt_qty,
            count(DISTINCT g.SSCC) AS Plt_qty,
            sum(g.Mass) as Mass
            FROM (
                SELECT DISTINCT ReportComm,
                Commgroup,
                MixedInd,
                id_variety
                from dim_variety
                WHERE ReportComm = lComm
            ) AS h,
            outgoing g force INDEX (outgoing_id_var_ship_date_derive_active)
            LEFT JOIN (SELECT sd.sail_date_id, sd.id_vessel, load_port, load_port_assign, 
                      shipped_date_derived, pv.shipped_date as sail_date, pv.zasaildate, 
                      pv.shipped_date_confirmed, pv.zasaildate_confirmed 
                    FROM agrihub.vessels_port_shipped_date sd
                    LEFT JOIN agrihub.vessels_sail_date pv ON (sd.sail_date_id=pv.id)) z 
                ON (z.id_vessel=g.id_vessel_derived AND g.SHIP_DATE_DERIVED=z.shipped_date_derived AND g.LOAD_PORT_DERIVED=z.load_port)
            LEFT JOIN ContainerInfo q ON (g.AGRIHUB_REF = q.Agrihub_ref),
            Report_Comm_Weeks j,
            StdEqvWeight k,
            dim_vessels v,
            dim_iso_ports m
            left join ppecb_region_country p ON(m.country = p.country)
            WHERE Active_flag = 'Y'
            AND REVISION <> '99'
            AND h.ReportComm = k.commodity
            AND h.ReportComm = lComm
            AND Ship_Weeks_DERIVED = j.week
            AND h.ReportComm = j.COMMODITY
            AND g.Country IN ('ZA', '  ')
            AND g.channel IN ('E', ' ')
           and g.TRANSPORT <>  if (linclude_airfreight = 'Y','^', 'A')
            AND g.id_variety = h.id_variety
            and g.id_vessel_derived = v.id_vessel
            AND lstart_date <= g.SHIP_DATE_DERIVED
            AND g.SHIP_DATE_DERIVED <= lend_date
            AND g.ID_PORT_DERIVED = m.id_ports
            AND NOT EXISTS (
                SELECT 1
                FROM mates k
                WHERE k.SSCC = g.SSCC
                AND k.SEQ_NO = g.SEQ_NO
                AND k.master_seasons = g.MASTER_SEASONS
                and Active = 'Y'
                and revision <> '99'
            )
            GROUP BY h.ReportComm,
            g.id_variety,

            /* Use vessel sail date from data_sail_date table in case NAVIS is not working */
            CASE WHEN z.shipped_date_confirmed = 1 THEN z.sail_date 
              WHEN z.shipped_date_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
              END,

            /* Use vessel zasail date from data_sail_date table where applicable */
            CASE WHEN z.zasaildate_confirmed = 1 THEN z.zasaildate 
              WHEN z.zasaildate_confirmed = 0 THEN date(now())
              WHEN g.id_vessel_derived = 0 THEN SHIP_DATE_DERIVED
              WHEN LEFT(g.LOAD_PORT_DERIVED,2) = 'MZ' THEN SHIP_DATE_DERIVED
              ELSE SHIP_DATE_DERIVED
              END,

            IF(z.zasaildate IS NOT NULL, z.zasaildate, '1900-01-01'),
            m.ISO_port_code,
            m.country,
            m.Region,
            g.TARGET_REGION_VALID,
            h.Commgroup,
            -- IF(z.load_port_assign IS NOT NULL, z.load_port_assign, g.LOAD_PORT_DERIVED) as LoadPort, -- 2022-02-08: update when vessels working is incorp
            g.LOAD_PORT_DERIVED,
            v.VesselName,
            g.ID_PORT_DERIVED,
            g.grade,
            q.OutboundVoyage,
            g.TRANSPORT,
            size_count,
            g.id_vessel_derived,
            z.sail_date_id
        ) AS ItAll

        LEFT JOIN dim_time t ON (date(t.the_date) = date(ItAll.ship_date_za))
        LEFT JOIN dim_time t2 ON (date(t2.the_date) = date(ItAll.ship_date_pol))
        GROUP BY ReportComm,
        id_variety,
        t2.week_season,
        t.week_season,
        ISO_port_code,
        country,
        PortRegion,
        TARGET_REGION_VALID,
        if (PortRegion = 'UNK', TARGET_REGION_VALID, PortRegion),
        Commgroup,
        LoadPort,
        VesselName,
        ID_PORT_DERIVED,
        ItAll.season,
        grade,
        OutboundVoyage,
        TRANSPORT,
        trim(size_count),
        id_vessel_derived,
        sail_date_id;

-- Get Airfreight Information

     if luse_airfreight_tbl = 'Y' 
     then

       INSERT INTO  SummaryTableTest20230508 (commodity,id_variety, shipped_week, shipped_week_za, shipped_week_pol,
          iso_port,port_country, port_region, exporter_region, combo_region,
          comm_grp, load_port, vesselname, id_port, seasons,
          grade, voyage,transport, size_count, id_vessel, act_ctns,eqv_ctns, plt_qty,mass)
      
       select h.ReportComm, a.id_variety,a.week,a.week,a.week,m.ISO_port_code, m.Country ,m.Region, m.Region, m.Region, h.CommGroup,
          'UNK', b.Vesselname,a.id_port,a.season,'UNK','UNK','A','UNK',2,
          0,sum(a.Mass)/k.MASS,0,sum(a.Mass )
          from airfreight a, dim_vessels b, 
        (SELECT DISTINCT ReportComm,Commgroup ,MixedInd,id_variety from dim_variety WHERE ReportComm = lcomm ) AS h ,
        StdEqvWeight k, dim_iso_ports m,( SELECT DISTINCT week_season FROM dim_time t
          										where t.the_date >= lstart_date AND t.end_date <= lend_date
                                    and t.season = lseason) q
          where b.id_vessel = 2
          and a.id_variety = h.id_variety
          and h.ReportComm = k.COMMODITY
          and a.id_port = m.id_ports
   --       AND t.the_date >= lstart_date AND t.end_date <= lend_date 
          AND q.week_season = a.week
   --       AND t.season = a.season
          AND h.ReportComm = lcomm
          and a.season = lseason
          GROUP BY h.ReportComm, a.id_variety,a.week,a.week,m.ISO_port_code, m.Country ,m.Region, m.Region, h.CommGroup,
          	 b.Vesselname,a.id_port,a.season;

     END IF ; -- if luse_airfreight_tbl = 'Y'

  end if ; -- if lComm ='DR' then

--      select lComm , lstart_date, lend_date,lseason , now();

      Fetch commoditylist into lComm, lstart_date, lend_date,lseason,luse_airfreight_tbl,linclude_airfreight  ;

    end while ;-- while not done do


    close commoditylist;
END$$
DELIMITER ;
