library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity filtre_video is
	generic (
			size	: integer := 8 	-- taille de la sous-fenetre = 2**size pixels
			);
    port (
			--horloge et reset
			CLK			: in std_logic; -- clock � 54 MHz
			RESET 		: in std_logic; -- reset � 0 			
			-- flux video � 27 MHz
			-- synchro
			VGA_X :	in std_logic_vector(10 downto 0); -- compteur pixels
			VGA_Y :	in std_logic_vector(10 downto 0); -- compteur lignes
			-- entr�e
			iY : 	in std_logic_vector(7 downto 0); -- flux video entrant : luminance
			iCb : 	in std_logic_vector(7 downto 0); -- flux video entrant : chrominance bleu
			iCr : 	in std_logic_vector(7 downto 0); -- flux video entrant : chrominance rouge
			-- sortie
			oY	: 	out std_logic_vector(7 downto 0); -- flux video sortant : luminance
			oCb	: 	out std_logic_vector(7 downto 0); -- flux video sortant : chrominance bleu
			oCr	: 	out std_logic_vector(7 downto 0); -- flux video sortant : chrominance rouge
			--switch D2E
			switch			: in std_logic_vector(17 downto 0)		-- � connecter � DPDT_SW;
			);			
end entity filtre_video;


architecture A of filtre_video is

component module_fenetrage
	generic (
			size			: integer := 8
			);
	port (
			VGA_X 			:	in std_logic_vector(10 downto 0);
			VGA_Y 			:	in std_logic_vector(10 downto 0);			
			iY 				: 	in std_logic_vector(7 downto 0);
			oY				: 	out std_logic_vector(7 downto 0);
			in_active_area 	:	out std_logic;
			X_cpt			:	out std_logic_vector(10 downto 0);
			Y_cpt			:	out std_logic_vector(10 downto 0)
		);
end component;


component memoire_ligne
  generic (
		address_size : integer;
		word_size : integer
		);
	port (
		CLK			: in std_logic;
		RESET		: in std_logic;		
		address 	: in std_logic_vector(address_size-1 downto 0);
		data_in		: in std_logic_vector(word_size-1 downto 0);
		data_out	: out std_logic_vector(word_size-1 downto 0);
		read_write	: in std_logic
		);	
end component;

component module_gradient
  port (
	in_active_area	: in std_logic;
	clk : in std_logic;
  reset	: in std_logic;
  synchro : in std_logic;
	iYd				: in std_logic_vector(7 downto 0) ; -- Current pixel
	iYu				: in std_logic_vector(7 downto 0) ; -- Pixel in the line memory (the pixel up to the current)
	oY				: out std_logic_vector(15 downto 0)
  ) ;
end component ; -- module_gradient


--signaux flux video
signal pixel_in		: std_logic_vector(7 downto 0) ;
signal grad		: std_logic_vector(15 downto 0) ;
signal pixel_out		: std_logic_vector(7 downto 0) ;

--signaux de synchro module fentrage
signal Y_cpt			: std_logic_vector(10 downto 0);
signal X_cpt 			: std_logic_vector(10 downto 0);
signal in_active_area 	: std_logic;

-- signaux memoire_ligne
signal adresse_memoire_ligne_current 	: std_logic_vector(size-1 downto 0);
signal adresse_memoire_ligne_next 	: std_logic_vector(size-1 downto 0);
signal read_write_memoire_ligne	: std_logic;
signal out_memoire_ligne		: std_logic_vector(7 downto 0) ;
signal X_curr		: std_logic_vector(10 downto 0) ;
signal X_next		: std_logic_vector(10 downto 0) ;

-- signal gradient
signal out_gradient		: std_logic_vector(15 downto 0) ;

--signaux de synchro
signal synchro_curr, synchro_next : std_logic; 							-- synchro pixel

--signaux adresses pour les deux memoires lignes
signal adresse_memoire_ligne1_current 	: std_logic_vector(size-1 downto 0);
signal adresse_memoire_ligne1_next 	: std_logic_vector(size-1 downto 0);
signal read_write_memoire_ligne1	: std_logic;
signal out_memoire_ligne1		: std_logic_vector(15 downto 0) ;



signal adresse_memoire_ligne2_current 	: std_logic_vector(size-1 downto 0);
signal adresse_memoire_ligne2_next 	: std_logic_vector(size-1 downto 0);
signal read_write_memoire_ligne2	: std_logic;
signal out_memoire_ligne2		: std_logic_vector(15 downto 0) ;


--signal pour g�rer le changement de ligne
signal change_ligne_curr : std_logic;
signal change_ligne_next : std_logic;

--Registres pour les pixels � gauche
signal R1_curr, R1_next, R2_curr, R2_next : std_logic_vector(15 downto 0);
signal R3_curr, R3_next, R4_curr, R4_next : std_logic_vector(15 downto 0);
signal R5_curr, R5_next, R6_curr, R6_next : std_logic_vector(15 downto 0);

--Angle et module
signal angle : std_logic_vector(2 downto 0);
signal module_curr, module_dir_plus, module_dir_moins : std_logic_vector(15 downto 0);
signal Gh, Gv : std_logic_vector(7 downto 0);

signal out_filtre : std_logic_vector(7 downto 0);

begin
	u_1: module_fenetrage 
	generic map(
			size => size
			)
	port map(
			VGA_X => VGA_X,
			VGA_Y => VGA_Y,			
			iY	=> iY,
			oY	=> pixel_in,
			in_active_area => in_active_area,
			X_cpt => X_cpt,
			Y_cpt => Y_cpt
			);
			
	u_2: memoire_ligne
	generic map (
	address_size   => size, 
	word_size => 8
	)
	port map(
			CLK => CLK,
			RESET => RESET,
			address 	=> adresse_memoire_ligne_current,
		  data_in		=> pixel_in,
		  data_out	=> out_memoire_ligne,
		  read_write	=> read_write_memoire_ligne
			);
	
	u_3 : module_gradient
	port map(
	   in_active_area	=> in_active_area,
	   clk => CLK,
	   reset => RESET,
	   synchro => synchro_curr,
	   iYd				=> pixel_in,
	   iYu				=> out_memoire_ligne, -- Pixel in the line memory (the pixel up to the current)
	   oY				=> out_gradient
	);
	
	u_4: memoire_ligne
	generic map (
	address_size   => size, 
	word_size => 16
	)
	port map(
			CLK => CLK,
			RESET => RESET,
			address 	=> adresse_memoire_ligne_current,
		  data_in		=> out_gradient,
		  data_out	=> out_memoire_ligne1,
		  read_write	=> read_write_memoire_ligne1
 );
			
	u_5: memoire_ligne
	generic map (
	address_size   => size, 
	word_size => 16
	)
	port map(
			CLK => CLK,
			RESET => RESET,
			address 	=> adresse_memoire_ligne_current,
		  data_in		=> out_gradient,
		  data_out	=> out_memoire_ligne2,
		  read_write	=> read_write_memoire_ligne2
	);			
			
			
	--process	
process_seq:process(clk)	-- clk � 27 MHz <=> 1 p�riodes en 1 pixel 
	begin	
	if (clk = '1' and clk'event) then 	
		if reset ='0' then -- reset actif		
			adresse_memoire_ligne_current <= (others => '0');
			adresse_memoire_ligne1_current <= (others => '0');
			adresse_memoire_ligne2_current <= (others => '0');
			change_ligne_curr <= '1';
			synchro_curr <= '1';
			R1_curr <= (others => '0');
			R2_curr <= (others => '0');
			R3_curr <= (others => '0');
			R4_curr <= (others => '0');
			R5_curr <= (others => '0');
			R6_curr <= (others => '0');
		else
			adresse_memoire_ligne_current <= adresse_memoire_ligne_next;
			synchro_curr <= synchro_next;
			change_ligne_curr <= change_ligne_next;
			R1_curr <= R1_next;
			R2_curr <= R2_next;
			R3_curr <= R3_next;
			R4_curr <= R4_next;
			R5_curr <= R5_next;
			R6_curr <= R6_next;
		end if;	
	end if;			
	end process process_seq;
--
 process_com : process( in_active_area, X_cpt, Y_cpt,adresse_memoire_ligne_current, synchro_curr, out_gradient)
	begin
	if in_active_area = '1'	then		-- zone active
		
		synchro_next <= not(synchro_curr) ;		-- g�n�ration signal de synchro pixel
						
		if synchro_curr = '1' then				-- cycle �criture
			read_write_memoire_ligne <= '1'; -- On active l'�criture	
			adresse_memoire_ligne_next <= adresse_memoire_ligne_current;				-- address conserv�e pour le cycle d'�criture
		  
		  
		else  								-- On ne fait rien mais on incr�mente la m�moire 
			read_write_memoire_ligne <= '0';					-- On d�sactive l'�criture
			if(to_integer(unsigned(X_cpt)) = 2**size+4) then
				adresse_memoire_ligne_next <= (others => '0');
			else
				adresse_memoire_ligne_next <= std_logic_vector(unsigned(adresse_memoire_ligne_current)+1);	
			end if;
		end if;		

	else 								-- zone inactive			

		synchro_next <= '1' ;		-- synchro inactive
		read_write_memoire_ligne <= '0';
    adresse_memoire_ligne_next <= (others => '0');
		
	end if;
	end process ; -- process_com /* 

	process_mem_grad : process( in_active_area, synchro_curr, change_ligne_curr, out_gradient)
	begin 
	 if in_active_area = '1' then	

	   if synchro_curr = '0' then
	     
	     if change_ligne_curr = '0' then
	       read_write_memoire_ligne1 <= '1'; 
	     else 
	       read_write_memoire_ligne2 <= '1'; 
	     end if;
	     	           
	   else 
	     read_write_memoire_ligne1 <= '0'; 
	     read_write_memoire_ligne2 <= '0'; 
	   
	   end if;
	   
	   
	 end if;
	end process;
	
	process_change_ligne : process(in_active_area, reset)
	begin
	   if in_active_area = '1' and reset = '1' then
	     change_ligne_next <= change_ligne_curr XOR '1';
	   end if;
	end process;
	
	process_recopie_registre : process(in_active_area, out_memoire_ligne1, out_memoire_ligne2, change_ligne_curr, R5_curr, R4_curr, R6_curr, out_gradient)
	begin
	  if in_active_area = '1' then
	    if change_ligne_curr = '0' then
	      R4_next <= out_memoire_ligne1;
	      R5_next <= out_memoire_ligne2;
	    else
	      R5_next <= out_memoire_ligne1;
	      R4_next <= out_memoire_ligne2;
	      
	    end if;
	    
	    R1_next <= R4_curr;
	    R2_next <= R5_curr;
	    
	    R6_next <= out_gradient;
	    R3_next <= R6_curr;
	 end if;
	    
	end process;
	

	
	process_tresh : process(in_active_area, out_memoire_ligne1, out_memoire_ligne2, change_ligne_curr, R1_curr, R2_curr, R3_curr, R4_curr, R5_curr, R6_curr, out_gradient)
	begin
	  
	  Gh <= R5_curr(15 downto 8);
	  Gv <= R5_curr(7 downto 0);

	  if in_active_area = '1' then
	    
	    -- Calcul module
	    module_curr <= std_logic_vector( unsigned(Gv) * unsigned(Gv) + unsigned(Gh) * unsigned(Gh) );
	    
	    -- Calcul angle
	    
	    -- Angle 0
      if (signed(Gv) < signed(Gh)/2 AND signed(Gv) > -signed(Gh)/2) then	      
        if change_ligne_curr = '0' then
	        module_dir_plus <= std_logic_vector( unsigned(out_memoire_ligne2(7 downto 0)) * unsigned(out_memoire_ligne2(7 downto 0)) + unsigned(out_memoire_ligne2(15 downto 8)) * unsigned(out_memoire_ligne2(15 downto 8)));
	      else
	        module_dir_plus <= std_logic_vector( unsigned(out_memoire_ligne1(7 downto 0)) * unsigned(out_memoire_ligne1(7 downto 0)) + unsigned(out_memoire_ligne1(15 downto 8)) * unsigned(out_memoire_ligne1(15 downto 8)));
        end if;
        
        module_dir_moins <= std_logic_vector(unsigned(R2_curr(7 downto 0)) * unsigned(R2_curr(7 downto 0)) + unsigned(R2_curr(15 downto 8)) * unsigned(R2_curr(15 downto 8)));
	    
	      if module_curr >= module_dir_moins and module_curr >= module_dir_plus then
	        out_filtre <= module_curr(7 downto 0);
	        
	      else
	        out_filtre <= "00000000";
	      end if;
      	    
 	    -- Angle Pi/4
	    else if signed(Gh)/2 < signed(Gv) then
	      if change_ligne_curr = '0' then
	        module_dir_plus <= std_logic_vector( unsigned(out_memoire_ligne1(7 downto 0)) * unsigned(out_memoire_ligne1(7 downto 0)) + unsigned(out_memoire_ligne1(15 downto 8)) * unsigned(out_memoire_ligne1(15 downto 8)));
	      else
	        module_dir_plus <= std_logic_vector( unsigned(out_memoire_ligne2(7 downto 0)) * unsigned(out_memoire_ligne2(7 downto 0)) + unsigned(out_memoire_ligne2(15 downto 8)) * unsigned(out_memoire_ligne2(15 downto 8)));
        end if;
        
        module_dir_moins <= std_logic_vector(unsigned(R3_curr(7 downto 0)) * unsigned(R3_curr(7 downto 0)) + unsigned(R3_curr(15 downto 8)) * unsigned(R3_curr(15 downto 8)));
	    
	    
	      if module_curr >= module_dir_moins and module_curr >= module_dir_plus then
	        out_filtre <= module_curr(7 downto 0);
	        
	      else
	        out_filtre <= "00000000";
	      end if;
	      
	    -- Angle -Pi/4
	    else if  signed(Gh)/2  < signed(Gv) AND signed(Gv) < -2*signed(Gh) then
	      module_dir_plus <= std_logic_vector( unsigned(out_gradient(7 downto 0)) * unsigned(out_gradient(7 downto 0)) + unsigned(out_gradient(15 downto 8)) * unsigned(out_gradient(15 downto 8)));
        module_dir_moins <= std_logic_vector(unsigned(R1_curr(7 downto 0)) * unsigned(R1_curr(7 downto 0)) + unsigned(R1_curr(15 downto 8)) * unsigned(R1_curr(15 downto 8)));

	      if module_curr >= module_dir_moins and module_curr >= module_dir_plus then
	        out_filtre <= module_curr(7 downto 0);
	        
	      else
	        out_filtre <= "00000000";
	      end if;
	      
	    -- Angle -Pi/ 2
	    else
	      module_dir_plus <= std_logic_vector( unsigned(R6_curr(7 downto 0)) * unsigned(R6_curr(7 downto 0)) + unsigned(R6_curr(15 downto 8)) * unsigned(R6_curr(15 downto 8)));
        module_dir_moins <= std_logic_vector(unsigned(R4_curr(7 downto 0)) * unsigned(R4_curr(7 downto 0)) + unsigned(R4_curr(15 downto 8)) * unsigned(R4_curr(15 downto 8)));

	      if module_curr >= module_dir_moins and module_curr >= module_dir_plus then
	        out_filtre <= module_curr(7 downto 0);
	        
	      else
	        out_filtre <= "00000000";
	    end if;
	    end if;
	    end if;
	    end if;
	    
	  else
	    out_filtre <= "00000000";
    end if;
	      
  end process;
	
	--process
	process_affichage : process( switch, iY, pixel_in, out_memoire_ligne, out_gradient)
	begin
		case( switch(4 downto 0) ) is
			when "00000" => oY <= iY; -- avant fenetrage		
			when "00001" => oY <= pixel_in; -- apr�s fenetrage				
			when "00011" => oY <= out_gradient(7 downto 0); -- apr�s grad
			when others  => oY <= out_filtre; -- apr�s diff
		end case ;
			
	end process ; -- process_affichage
	
	

end architecture A;	