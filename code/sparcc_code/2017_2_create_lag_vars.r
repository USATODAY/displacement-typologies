# ==========================================================================
# SPARCC data setup
# ==========================================================================

if(!require(pacman)) install.packages("pacman")
p_load(colorout, data.table, tigris, tidycensus, tidyverse, spdep)
# options(width = Sys.getenv('COLUMNS'))

# census_api_key("your_api_key_here", install = TRUE)

# ==========================================================================
# Pull in data
# ==========================================================================
# Note: Adjust the cities below if there are additional cities - add your city here

df <- 
    bind_rows(
            read_csv("~/git/sparcc/data/outputs/Atlanta_database_2017.csv") %>% 
            select(!X1) %>% 
            mutate(city = "Atlanta"),
            read_csv("~/git/sparcc/data/outputs/Denver_database_2017.csv") %>% 
            select(!X1) %>% 
            mutate(city = "Denver"),
            read_csv("~/git/sparcc/data/outputs/Chicago_database_2017.csv") %>% 
            select(!X1) %>% 
            mutate(city = "Chicago"),
            read_csv("~/git/sparcc/data/outputs/Memphis_database_2017.csv") %>% 
            select(!X1) %>% 
            mutate(city = "Memphis")
    )

# ==========================================================================
# Create rent gap and extra local change in rent
# ==========================================================================

#
# Tract data
# --------------------------------------------------------------------------
# Note: Make sure to extract tracts that surround cities. For example, in 
# Memphis and Chicago, TN, MO, MS, and AL are within close proximity of 
# Memphis and IN is within close proximity of Chicago. 

### Tract data extraction function: add your state here
st <- c("IL","GA","AR","TN","CO","MS","AL","KY","MO","IN")

tr_rent <- function(year, state){
    get_acs(
        geography = "tract",
        variables = c('medrent' = 'B25064_001'),
        state = state,
        county = NULL,
        geometry = FALSE,
        cache_table = TRUE,
        output = "tidy",
        year = year,
        keep_geo_vars = TRUE
        ) %>%
    select(-moe) %>% 
    rename(medrent = estimate) %>% 
    mutate(
        county = str_sub(GEOID, 3,5), 
        state = str_sub(GEOID, 1,2),
        year = str_sub(year, 3,4) 
    )
}

### Loop (map) across different states
tr_rents17 <- 
    map_dfr(st, function(state){
        tr_rent(year = 2017, state) %>% 
        mutate(COUNTY = substr(GEOID, 1, 5))
    })

tr_rents12 <- 
    map_dfr(st, function(state){
        tr_rent(year = 2012, state) %>% 
        mutate(
            COUNTY = substr(GEOID, 1, 5),
            medrent = medrent*1.07)
    })


tr_rents <- 
    bind_rows(tr_rents17, tr_rents12) %>% 
    unite("variable", c(variable,year), sep = "") %>% 
    group_by(variable) %>% 
    spread(variable, medrent) %>% 
    group_by(COUNTY) %>%
    mutate(
        tr_medrent17 = 
            case_when(
                is.na(medrent17) ~ median(medrent17, na.rm = TRUE),
                TRUE ~ medrent17
            ),
        tr_medrent12 = 
            case_when(
                is.na(medrent12) ~ median(medrent12, na.rm = TRUE),
                TRUE ~ medrent12),
        tr_chrent = tr_medrent17 - tr_medrent12,
        tr_pchrent = (tr_medrent17 - tr_medrent12)/tr_medrent12, 
### CHANGE THIS TO INCLUDE RM of region rather than county
        rm_medrent17 = median(tr_medrent17, na.rm = TRUE), 
        rm_medrent12 = median(tr_medrent12, na.rm = TRUE)) %>% 
    select(-medrent12, -medrent17) %>% 
    distinct() %>% 
    group_by(GEOID) %>% 
    filter(row_number()==1) %>% 
    ungroup()

# Pull in state tracts shapefile and unite them into one shapefile
    #Add your state here
states <- 
    raster::union(
        tracts("IL", cb = TRUE, class = 'sp'), 
        tracts("GA", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("AR", cb = TRUE, class = 'sp')) %>%  
    raster::union(tracts("TN", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("CO", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("MS", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("AL", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("KY", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("MO", cb = TRUE, class = 'sp')) %>%
    raster::union(tracts("IN", cb = TRUE, class = 'sp'))
    
stsp <- states

# join data to these tracts
stsp@data <-
    left_join(
        stsp@data %>% 
        mutate(GEOID = case_when(
            !is.na(GEOID.1) ~ GEOID.1, 
            !is.na(GEOID.2) ~ GEOID.2, 
            !is.na(GEOID.1.1) ~ GEOID.1.1, 
            !is.na(GEOID.1.2) ~ GEOID.1.2, 
            !is.na(GEOID.1.3) ~ GEOID.1.3), 
    ), 
        tr_rents, 
        by = "GEOID") %>% 
    select(GEOID:rm_medrent12)



#
# Create neighbor matrix
# --------------------------------------------------------------------------
    coords <- coordinates(stsp)
    IDs <- row.names(as(stsp, "data.frame"))
    stsp_nb <- poly2nb(stsp) # nb
    lw_bin <- nb2listw(stsp_nb, style = "W", zero.policy = TRUE)

    kern1 <- knn2nb(knearneigh(coords, k = 1), row.names=IDs)
    dist <- unlist(nbdists(kern1, coords)); summary(dist)
    max_1nn <- max(dist)
    dist_nb <- dnearneigh(coords, d1=0, d2 = .1*max_1nn, row.names = IDs)
    spdep::set.ZeroPolicyOption(TRUE)
    spdep::set.ZeroPolicyOption(TRUE)
    dists <- nbdists(dist_nb, coordinates(stsp))
    idw <- lapply(dists, function(x) 1/(x^2))
    lw_dist_idwW <- nb2listw(dist_nb, glist = idw, style = "W")
    

#
# Create select lag variables
# --------------------------------------------------------------------------

    stsp$tr_pchrent.lag <- lag.listw(lw_dist_idwW,stsp$tr_pchrent)
    stsp$tr_chrent.lag <- lag.listw(lw_dist_idwW,stsp$tr_chrent)
    stsp$tr_medrent17.lag <- lag.listw(lw_dist_idwW,stsp$tr_medrent17)

# ==========================================================================
# Join lag vars with df
# ==========================================================================

lag <-  
    left_join(
        df, 
        stsp@data %>% 
            mutate(GEOID = as.numeric(GEOID)) %>%
            select(GEOID, tr_medrent17:tr_medrent17.lag)) %>%
    mutate(
        tr_rent_gap = tr_medrent17.lag - tr_medrent17, 
        tr_rent_gapprop = tr_rent_gap/((tr_medrent17 + tr_medrent17.lag)/2),
        rm_rent_gap = median(tr_rent_gap, na.rm = TRUE), 
        rm_rent_gapprop = median(tr_rent_gapprop, na.rm = TRUE), 
        rm_pchrent = median(tr_pchrent, na.rm = TRUE),
        rm_pchrent.lag = median(tr_pchrent.lag, na.rm = TRUE),
        rm_chrent.lag = median(tr_chrent.lag, na.rm = TRUE),
        rm_medrent17.lag = median(tr_medrent17.lag, na.rm = TRUE), 
        dp_PChRent = case_when(tr_pchrent > 0 & 
                               tr_pchrent > rm_pchrent ~ 1, # ∆ within tract
                               tr_pchrent.lag > rm_pchrent.lag ~ 1, # ∆ nearby tracts
                               TRUE ~ 0),
        dp_RentGap = case_when(tr_rent_gapprop > 0 & tr_rent_gapprop > rm_rent_gapprop ~ 1,
                               TRUE ~ 0),
    ) 

# ==========================================================================
# PUMA
# ==========================================================================

puma <-
    get_acs(
        geography = "public use microdata area", 
        variable = "B05006_001", 
        year = 2017, 
        geometry = TRUE,
        keep_geo_vars = TRUE, 
        state = c("GA", "TN", "IL", "CO")) %>% 
    mutate(
        sqmile = ALAND10/2589988, 
        puma_density = estimate/sqmile
        ) %>% 
    select(puma_density)

stsf <- 
    stsp %>% 
    st_as_sf() %>% 
    st_transform(4269) %>% 
    st_centroid() %>%
    st_join(., puma) %>% 
    mutate(dense = case_when(puma_density >= 3000 ~ 1, TRUE ~ 0)) %>% 
    st_drop_geometry() %>% 
    select(GEOID, puma_density, dense) %>% 
    mutate(GEOID = as.numeric(GEOID))

lag <- 
    left_join(lag, stsf)

# ==========================================================================
# At risk of gentrification (ARG)
# Risk = Vulnerability, cheap housing, hot market (rent-gap & extra local change)
# ==========================================================================

    # group_by(GEOID) %>% 
    # mutate(
    #     ARG2 = 
    #         case_when(
    #             pop00flag == 1 & 
    #             (low_pdmt_medhhinc_17 == 1 | mix_low_medhhinc_17 == 1) & 
    #             (lmh_flag_encoded == 1 | lmh_flag_encoded == 4) & 
    #             (change_flag_encoded == 1 | change_flag_encoded == 2) &
    #             gent_90_00 == 0 &
    #             (dp_PChRent == 1 | dp_RentGap == 1) & # new
    #             vul_gent_00 == 1 & # new
    #             gent_00_17 == 0 ~ 1, 
    #             TRUE ~ 0), 
    #     # trueARG = case_when(ARG == ARG2 ~ TRUE, TRUE ~ FALSE)
    #     typ_cat2 = 
    #         case_when(
    #             SLI == 1 ~ "SLI",
    #             OD == 1 ~ "OD",
    #             ARG2 == 1 ~ "ARG", # ARG2!!
    #             EOG == 1 ~ "EOG",
    #             AdvG == 1 ~ "AdvG",
    #             SMMI == 1 ~ "SMMI",
    #             ARE == 1 ~ "ARE",
    #             BE == 1 ~ "BE",
    #             SAE == 1 ~ "SAE",
    #             double_counted > 1 ~ "double_counted"
    #         )
    # )

# saveRDS(df2, "~/git/sparcc/data/rentgap.rds")
fwrite(lag, "~/git/sparcc/data/outputs/lag_2017.csv")

# df2 %>% filter(GEOID == 13121006000) %>% glimpse()