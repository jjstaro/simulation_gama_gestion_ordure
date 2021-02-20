/***
* Name: model
* Author: Franck Anael MBIAYA, Kein KANA, Jérémie OUEDRAOGO
* Description: Simulation de la gestion des ordures dans une ville
***/

model g7gestionordure

/* Insert your model definition here */

global {
	
	file routes <- file("../includes/routes.shp");
	file batiments <- file("../includes/Building.shp");
	file depots <- file("../includes/Depots.shp");
	file poubelles <- file("../includes/Poubelles.shp");
	file traitement <- file("../includes/Traitement.shp");
	
	geometry shape <- envelope(routes);
	graph route_network;
	
	int nbre_Camion_urbain <- 2 parameter:'Nombre de benne à ordure par entrepôt' category: 'Transport' min:1 max:5;
	int nbre_Camion_traitement <- 3 parameter:'Nombre de camion à ordure' category: 'Transport' min:1 max:5;
	float proba_remplissage <- 1/5 parameter:'Probabilité de remplissage des bacs à ordure' category: 'Transport' min:0.0 max:1.0;
	float vitesse_traitement_dechets <- 18.0 parameter:'Vitesse de traitement des déchets' category: 'Transport' min:10.0 max:50.0;
	
	init {
		create Route from: routes;
		route_network <- as_edge_graph(Route, 10);	
		create Habitation from: batiments;
		create Entrepot from: depots;
		create BacOrdure from: poubelles;
		create CentreTraitementDechet from: traitement;
	}
}

/*
 * Agent représentant tout type de véhicule
 */
species Vehicule skills:[moving] {  
    float charge_max;
    float charge_actuelle;
    rgb color;
    float size;
    int index_objectif init: 0;
    bool deplacement init: false;
    point objectif;
    int frequence_vidange;
    int compteur_temps init: 0;
    
    aspect default {
    	draw circle(size) color: color;
    }
    
    reflex move when: deplacement{
    	do goto target: objectif on: route_network;
    }
}

/*
 * Camion qui recupère les ordures dans la ville
 */
species BenneOrdure parent: Vehicule {
	list<BacOrdure> liste_objectifs;
	Entrepot maison;
	
	init {
		speed <- 5.0 + rnd(5.0);
		size <- 6.0;
		color <- rgb(5, 42, 246);
		charge_max <- 2000.0;
		frequence_vidange <- rnd(300, 600);
	}
	
	reflex temps {
		if !deplacement {
			compteur_temps <- compteur_temps + 1;
			
			if compteur_temps >= frequence_vidange {
				compteur_temps <- 0;
				deplacement <- true;
				index_objectif <- 0;
				objectif <- any_location_in(liste_objectifs at index_objectif);
			}
		} else {
			// Si on est dans l'entrepôt
			if agents_inside(maison) index_of self != -1 {
				// On ne bouge plus jusqu'à ce que la benne soit vide
				if charge_actuelle > 0 {
					objectif <- nil;
				} else {
					// S'il faur encore rentrer vers le dernier bac à ordures
					if (liste_objectifs at index_objectif).charge_actuelle > (liste_objectifs at index_objectif).charge_max / 10 {
						objectif <- any_location_in(liste_objectifs at index_objectif);
					} else
					// On vérifie qu'il ya encore un trajet à faire
					if index_objectif < (length(liste_objectifs) - 1) {
						index_objectif <- index_objectif + 1;
		    			objectif <- any_location_in(liste_objectifs at index_objectif);
					} else { // Sinin on arrete le déplacement
						index_objectif <- 0;
						compteur_temps <- 0;
						deplacement <- false;
					}
				}
			}
		}
	}
    
    // Pour vidanger un bac à ordure lorsqu'on est à proximité d'elle et lorsque c'est notre objectif
    reflex vidange_bac_ordure when: deplacement and (agents_inside(objectif) index_of self != -1){
    	// Si le camion a encore la capacité de charger
    	if charge_actuelle + 6 < charge_max{
    		ask (liste_objectifs at index_objectif) {
    			float quantite_decharge <- min(50.0, myself.charge_max - myself.charge_actuelle, self.charge_actuelle);
    			do decharge qnte: quantite_decharge;
    			myself.charge_actuelle <- myself.charge_actuelle + quantite_decharge;
    			
    			// Si le bac à ordure est vide, on se retire
		    	if self.charge_actuelle = 0 {
		    		// si il ya encore des bacs à décharger
		    		if myself.index_objectif < (length(myself.liste_objectifs) - 1) {
		    			myself.index_objectif <- myself.index_objectif + 1;
		    			myself.objectif <- any_location_in(myself.liste_objectifs at myself.index_objectif);
		    		} else { // Sinon on rentre à l'entrepôt
		    			myself.objectif <- any_location_in(myself.maison);
		    		}
		    	}
    		}
    	} else { // On va d'abord décharger à l'entrepôt
    		objectif <- any_location_in(maison);
    	}
    }
   
    
    // Vidange dans l'entrepôt si le camion contient des ordures
    reflex vidange_dans_entrepot when:(agents_inside(maison) index_of self != -1) and charge_actuelle > 0 {
    	ask maison{
    		float quantite_decharge <- min([60.0, myself.charge_actuelle]);
    		quantite_decharge <- charge_dans_depot(quantite_decharge);
    		myself.charge_actuelle <- myself.charge_actuelle - quantite_decharge;
    	}
    }
}

/*
 * Camion qui recupère les ordures dans les entrepôts pour les déversser au centre de traitement des déchets (Entrepot)
 */
species CamionOrdure parent: Vehicule {
	list<Entrepot> liste_objectifs;
	CentreTraitementDechet maison;
	
	init {
		speed <- 7.0 + rnd(4.0);
		size <- 8.0;
		color <- rgb(200, 20, 120);
		charge_max <- 3500.0;
		frequence_vidange <- rnd(1000, 1500);
	}
	
	reflex temps {
		if !deplacement {
			compteur_temps <- compteur_temps + 1;
			
			if compteur_temps >= frequence_vidange {
				compteur_temps <- 0;
				deplacement <- true;
				index_objectif <- 0;
				objectif <- any_location_in(liste_objectifs at index_objectif);
			}
		} else {
			// Si on est dans le centre de traitemnt
			if agents_inside(maison) index_of self != -1 {
				// On ne bouge plus jusqu'à ce que la benne soit vide
				if charge_actuelle > 0 {
					objectif <- nil;
				} else {
					// S'il faur encore rentrer vers le dernier bac à ordures
					if (liste_objectifs at index_objectif).charge_actuelle > (liste_objectifs at index_objectif).charge_max / 10 {
						objectif <- any_location_in(liste_objectifs at index_objectif);
					} else
					// On vérifie qu'il ya encore un trajet à faire
					if index_objectif < (length(liste_objectifs) - 1) {
						index_objectif <- index_objectif + 1;
		    			objectif <- any_location_in(liste_objectifs at index_objectif);
					} else { // Sinin on arrete le déplacement
						deplacement <- false;
					}
				}
			}
		}
	}
    
    // Pour vidanger un entrepot lorsqu'on est à proximité de lui et lorsque c'est notre objectif
    reflex vidange_entrepot when: deplacement and (agents_inside(objectif) index_of self != -1){
    	// Si le camion a encore la capacité de charger
    	if charge_actuelle < charge_max{
    		ask (liste_objectifs at index_objectif) {
    			float quantite_decharge <- min(100.0, myself.charge_max - myself.charge_actuelle, self.charge_actuelle);
    			do decharge qnte: quantite_decharge;
    			myself.charge_actuelle <- myself.charge_actuelle + quantite_decharge;
    			
    			// Si l'entrepot est vide, on se retire
		    	if self.charge_actuelle = 0 {
		    		// si il ya encore des entrepots à décharger
		    		if myself.index_objectif < (length(myself.liste_objectifs) - 1) {
		    			myself.index_objectif <- myself.index_objectif + 1;
		    			myself.objectif <- any_location_in(myself.liste_objectifs at myself.index_objectif);
		    		} else { // Sinon on rentre à au centre de traitement
		    			myself.objectif <- any_location_in(myself.maison);
		    		}
		    	}
    		}
    	} else { // On va d'abord décharger au centre de traitement
    		objectif <- any_location_in(maison);
    	}
    }
    
    // Vidange dans le centre de traitement si le camion contient des ordures
    reflex vidange_dans_centre_traitement when:(agents_inside(maison) index_of self != -1) and charge_actuelle > 0 {
    	ask maison{
    		float quantite_decharge <- min([150.0, myself.charge_actuelle]);
    		quantite_decharge <- charge_dans_centre(quantite_decharge);
    		myself.charge_actuelle <- myself.charge_actuelle - quantite_decharge;
    	}
    }
}

species Route {
	aspect basic {
		draw line(shape.points, 1) color: #gray border: #black;
	}
}

species Habitation {
	aspect basic {
		draw shape color: #gray;
	}
}

species Entrepot {
	float charge_max <- rnd(7000.0, 10000.0);
	float charge_actuelle <- rnd(5000.0);
	list<BacOrdure> list_bac_ordure;
	list<list<BacOrdure>> liste_parcourt;
	bool parcourt <- false;
	rgb color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);

	init{	    
		// On crée les bennes à ordures de cet entrepôt
		create BenneOrdure number: nbre_Camion_urbain {
	        location <- any_location_in(myself);
	        maison <- myself;
	    }
	}
	
	action creer_parcourt {
		// On crée le parcourt de chaque benne à ordures
	    int nbre_bac_par_benne <- int(length(list_bac_ordure) / nbre_Camion_urbain);
	    // On initialise chaque parcourt
	    loop i from: 0 to: nbre_Camion_urbain step:1 {
	    	list<BacOrdure> liste_bac;
	    	add item:liste_bac to: liste_parcourt;
	    }
	    
	    // On range la liste des bacs par ordre de distance j'usqu'à l'entrepot 
	    list_bac_ordure <- list_bac_ordure sort_by (self distance_to each);
	    
	    int i <- 0;
	    int compteur <- 0;
	    // On répartie les bac à ordure
	    loop j from: 0 to: length(list_bac_ordure)-1 step:1 {
	    	if compteur - nbre_bac_par_benne = 0 and (i+1) < length(liste_parcourt) {
	    		i <- i + 1;
	    		compteur <- 0;
	    	} else {
	    		compteur <- compteur + 1;
	    	}
	    	add item:(list_bac_ordure at j) to: (liste_parcourt at i);
	    }
	    
	    // On attribut à chaque benne à ordure son parcourt
	    i <- 0;
	    ask BenneOrdure where (each.maison = self) {
	    	self.liste_objectifs <- (myself.liste_parcourt at i);
	    	i <- i + 1;
	    }
	}
	
	// Pour créer les parcours
	reflex initialiser_parcourt when: !parcourt {
		do creer_parcourt;
		parcourt <- true;
	}
	
	// Pour les bennes qui veulent déversser les ordures dans l'entrepôt
	float charge_dans_depot (float qnte){
    	if charge_actuelle + qnte <= charge_max {
    		charge_actuelle <- charge_actuelle + qnte;
    		color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);
    		return qnte;
    	}
    	return 0;
    }
    
    action decharge (float qnte){
    	charge_actuelle <- charge_actuelle - qnte;
    	color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);
    }
	
	aspect basic {
		draw shape color: color border:rgb(5, 42, 246);
	}
}

species BacOrdure {
	float charge_max init: 255.0;
	float charge_actuelle init: rnd(255.0) max: charge_max;
	rgb color <- rgb(charge_actuelle,255-charge_actuelle,0);
	
	init{
		Entrepot depot <- (agents of_species Entrepot) closest_to(self);
		add item: self to:depot.list_bac_ordure;
	}
	
	action decharge (float qnte){
    	charge_actuelle <- charge_actuelle - qnte;
    	color <- rgb(charge_actuelle,255-charge_actuelle,0);
    }
	
	aspect basic {
		draw shape color: color border:#gray;
	}
	
	reflex remplissag_bac_ordure when: charge_actuelle < charge_max{
		if flip(rnd(proba_remplissage)){
			charge_actuelle <- charge_actuelle + rnd(5);
			color <- rgb(charge_actuelle,255-charge_actuelle,0);
		}
	}
}

species CentreTraitementDechet {
	float charge_max <- 20000.0;
	float charge_actuelle init: rnd(10000.0) max: charge_max min: 0.0;
	float vitesse_traitement <- vitesse_traitement_dechets;
	list<Entrepot> list_entrepot <- agents of_generic_species Entrepot;
	list<list<Entrepot>> liste_parcourt;
	rgb color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);
	bool parcourt <- false;
	
	init {
		create CamionOrdure number: nbre_Camion_traitement {
			maison <- one_of(CentreTraitementDechet);
	        location <- any_location_in(maison);
	    }
	}
	
	aspect basic {
		draw shape color: color border:rgb(200, 20, 120);
	}
	
	action creer_parcourt {
		// On crée le parcourt de chaque camion à ordures
	    int nbre_entrepot_par_camion <- round(length(list_entrepot) / length(agents of_generic_species CamionOrdure));
	    // On initialise chaque parcourt
	    loop i from: 0 to: length(agents of_generic_species Entrepot) step:1 {
	    	list<Entrepot> liste_entrepo;
	    	add item: liste_entrepo to: liste_parcourt;
	    }
	    
	    // On range la liste des entrepots par ordre de distance j'usqu'à l'entrepot 
	    list_entrepot <- list_entrepot sort_by (self distance_to each);
	    
	    int i <- 0;
	    int compteur <- 0;
	    // On répartie les entrepots
	    loop j from: 0 to: length(list_entrepot)-1 step:1 {
	    	if compteur - nbre_entrepot_par_camion = 0 and (i+1) < length(liste_parcourt) {
	    		i <- i + 1;
	    		compteur <- 0;
	    	} else {
	    		compteur <- compteur + 1;
	    	}
	    	add item:(list_entrepot at j) to: (liste_parcourt at i);
	    }
	    
	    // On attribut à chaque benne à ordure son parcourt
	    i <- 0;
	    ask CamionOrdure {
	    	self.liste_objectifs <- (myself.liste_parcourt at i);
	    	i <- i + 1;
	    }
	}
	
	// Pour créer les parcours
	reflex initialiser_parcourt when: !parcourt {
		do creer_parcourt;
		parcourt <- true;
	}
	
	// Pour les camion qui veulent déversser les ordures dans l'entrepôt
	float charge_dans_centre (float qnte){
    	if charge_actuelle + qnte <= charge_max {
    		charge_actuelle <- charge_actuelle + qnte;
    		color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);
    		return qnte;
    	}
    	return 0;
    }
	
	// Traitement des déchets en fonction de la vitesse de traitement
	reflex traitement_dechet when: charge_actuelle > vitesse_traitement {
		charge_actuelle <- charge_actuelle - vitesse_traitement;
		color <- rgb(charge_actuelle/(charge_max/255),255-(charge_actuelle/(charge_max/255)),0);
	}
}

experiment main type: gui{
    
	output {
    	
		display NewYork2D type: opengl {
			species Route aspect:basic;
			species Habitation aspect:basic;
			species Entrepot aspect:basic;
			species BacOrdure aspect:basic;
			species CentreTraitementDechet aspect:basic;
			species CamionOrdure aspect:default;
			species BenneOrdure aspect:default;
		}
	}
}

