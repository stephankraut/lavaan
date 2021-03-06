# YR 11 feb 2017: initial version

# given a parameter table (PT), extract a part of the model:
# eg.:
# - only the measurement model (with saturated latent variables)
# - only the stuctural part
# - a single measurement block
# ...


# FIXME:
# - if we have more than 1 factor, we remove the structural
#   part, but should we add ALL correlations among the latent variables?
#   (YES for now, if add.lv.cov = TRUE)
# - but fixed-to-zero covariances may not be present in PT...
#
lav_partable_subset_measurement_model <- function(PT = NULL,
                                                  lavpta = NULL,
                                                  lv.names = NULL,
                                                  add.lv.cov = TRUE,
                                                  add.idx = FALSE,
                                                  idx.only = FALSE) {

    # PT
    PT <- as.data.frame(PT, stringsAsFactors = FALSE)

    # lavpta
    if(is.null(lavpta)) {
        lavpta <- lav_partable_attributes(PT)
    }

    # nblocks
    nblocks <- lavpta$nblocks
    block.values <- lav_partable_block_values(PT)

    # lv.names: list with element per block
    if(is.null(lv.names)) {
        lv.names <- lavpta$vnames$lv.regular
    } else if(!is.list(lv.names)) {
        lv.names <- rep(list(lv.names), nblocks)
    }

    # keep rows idx
    keep.idx <- integer(0L)

    # remove not-needed measurement models
    for(g in 1:nblocks) {
        # indicators for latent variables we keep
        IND.idx <- which(  PT$op == "=~"              &
                           PT$lhs %in% lv.names[[g]]  &
                           PT$block == block.values[g] )
        IND <- PT$rhs[ IND.idx ]
        IND.plabel <- PT$plabel[ IND.idx ]

        # keep =~
        keep.idx <- c(keep.idx, IND.idx)

        # keep ~~
        OV.VAR.idx <- which( PT$op == "~~"   &
                             PT$lhs %in% IND &
                             PT$rhs %in% IND &
                             PT$block == block.values[g] )
        keep.idx <- c(keep.idx, OV.VAR.idx)

        LV.VAR.idx <- which( PT$op == "~~"             &
                             PT$lhs %in% lv.names[[g]] &
                             PT$rhs %in% lv.names[[g]] &
                             PT$block == block.values[g] )
        keep.idx <- c(keep.idx, LV.VAR.idx)

        # intercepts indicators
        OV.INT.idx <- which( PT$op == "~1"    &
                             PT$lhs %in% IND  &
                             PT$block == block.values[g] )
        keep.idx <- c(keep.idx, OV.INT.idx)

        # intercepts latent variables
        LV.INT.idx <- which( PT$op == "~1"                 &
                             PT$lhs %in% lv.names[[g]]  &
                             PT$block == block.values[g] )
        keep.idx <- c(keep.idx, LV.INT.idx)

        # thresholds
        TH.idx <- which( PT$op == "|"    &
                         PT$lhs %in% IND &
                         PT$block == block.values[g] )
        keep.idx <- c(keep.idx, TH.idx)

        # scaling factors
        SC.idx <- which( PT$op == "~*~"  &
                         PT$lhs %in% IND &
                         PT$block == block.values[g] )
        keep.idx <- c(keep.idx, SC.idx)

        # FIXME: ==, :=, <, >, == involving IND...

        # `simple' == constraints (simple lhs and rhs)
        #EQ.idx <- which(PT$op == "==" &
        #                PT$lhs %in% IND.plabel &
        #                PT$rhs %in% IND.plabel)

        con.idx <- which(PT$op %in% c("==","<",">",":="))
        if(length(con.idx) > 0L) {
            ID <- lav_partable_constraints_label_id(PT, def = TRUE)
            LABEL <- names(ID)
            con.keep <- logical( length(con.idx) )
            for(con in seq_len(length(con.idx))) {

                lhs.keep <- FALSE
                rhs.keep <- FALSE


                # lhs
                if(PT[con.idx[con],"op"] == ":=") {
                    lhs.keep <- TRUE
                } else {
                    LHS.labels <- all.vars(as.formula(paste("~",
                                           PT[con.idx[con],"lhs"])))
                    if(length(LHS.labels) > 0L) {
                        # par id
                        LHS.freeid <- ID[match(LHS.labels, LABEL)]

                        # keep?
                        if(all(LHS.freeid %in% PT$free[keep.idx])) {
                            lhs.keep <- TRUE
                        }
                    } else {
                        lhs.keep <- TRUE
                    }
                }



                # rhs
                RHS.labels <- all.vars(as.formula(paste("~",
                                       PT[con.idx[con],"rhs"])))
                if(length(RHS.labels) > 0L) {
                    # par id
                    RHS.freeid <- ID[match(RHS.labels, LABEL)]

                    # keep?
                    if(all(RHS.freeid %in% PT$free[keep.idx])) {
                        rhs.keep <- TRUE
                    }
                } else {
                    rhs.keep <- TRUE
                }

                if(lhs.keep && rhs.keep) {
                    con.keep[con] <- TRUE
                }
            }

            EQ.idx <- con.idx[ con.keep ]
            keep.idx <- c(keep.idx, EQ.idx)
        } # con

    } # block

    if(idx.only) {
        return(keep.idx)
    }

    PT <- PT[keep.idx,,drop = FALSE]

    # check if we have enough indicators?
    # TODO

    # add covariances among latent variables?
    if(add.lv.cov) {
        PT <- lav_partable_add_lv_cov(PT = PT, lavpta = lavpta,
                                      lv.names = lv.names)
    }

    # clean up
    PT <- lav_partable_complete(PT)

    if(add.idx) {
        attr(PT, "idx") <- keep.idx
    }

    PT
}

# NOTE: only within same level
lav_partable_add_lv_cov <- function(PT, lavpta = NULL, lv.names = NULL) {

    # PT
    PT <- as.data.frame(PT, stringsAsFactors = FALSE)

    # lavpta
    if(is.null(lavpta)) {
        lavpta <- lav_partable_attributes(PT)
    }

    # nblocks
    nblocks <- lavpta$nblocks
    block.values <- lav_partable_block_values(PT)


    # lv.names: list with element per block
    if(is.null(lv.names)) {
        lv.names <- lavpta$vnames$lv.regular
    } else if(!is.list(lv.names)) {
        lv.names <- rep(list(lv.names), nblocks)
    }

    # remove lv.names if not present at same level/block
    if(nblocks > 1L) {
        for(b in seq_len(nblocks)) {
            rm.idx <- which(!lv.names[[b]] %in% lavpta$vnames$lv.regular[[b]])
            if(length(rm.idx) > 0L) {
                lv.names[[b]] <- lv.names[[b]][-rm.idx]
            }
        } # b
    }

    # add covariances among latent variables
    for(b in seq_len(nblocks)) {
        if(length(lv.names[[b]]) > 1L) {
            tmp <- utils::combn(lv.names[[b]], 2L)
            for(i in ncol(tmp)) {

                # already present?
                cov1.idx <- which(PT$op == "~~" &
                                  PT$block == block.values[b] &
                                  PT$lhs == tmp[1,i] & PT$rhs == tmp[2,i])
                cov2.idx <- which(PT$op == "~~" &
                                  PT$block == block.values[b] &
                                  PT$lhs == tmp[2,i] & PT$rhs == tmp[1,i])

                # if not, add
                if(length(c(cov1.idx, cov2.idx)) == 0L) {
                    ADD = list(lhs   = tmp[1,i],
                               op    = "~~",
                               rhs   = tmp[2,i],
                               user  = 3L,
                               free  = max(PT$free) + 1L,
                               block = b)
                    # add group column
                    if(!is.null(PT$group)) {
                        ADD$group <- unique(PT$block[PT$block == b])
                    }
                    # add level column
                    if(!is.null(PT$level)) {
                        ADD$level <- unique(PT$level[PT$block == b])
                    }
                    PT <- lav_partable_add(PT, add = ADD)
                }
            }

        } # lv.names
    } # blocks

    PT
}


# this function takes a 'full' SEM (measurement models + structural part)
# and returns only the structural part
#
# - what to do if we have no regressions among the latent variables?
#   we return all covariances among the latent variables
#
# - also, we should check if we have any 'higher' order factors
#
lav_partable_subset_structural_model <- function(PT = NULL,
                                                 lavpta = NULL,
                                                 add.idx = FALSE,
                                                 idx.only = FALSE) {

    # PT
    PT <- as.data.frame(PT, stringsAsFactors = FALSE)

    # lavpta
    if(is.null(lavpta)) {
        lavpta <- lav_partable_attributes(PT)
    }

    # nblocks
    nblocks <- lavpta$nblocks
    block.values <- lav_partable_block_values(PT)

    # eqs.names
    eqs.x.names <- lavpta$vnames$eqs.x
    eqs.y.names <- lavpta$vnames$eqs.y
    lv.names    <- lavpta$vnames$lv.regular

    # keep rows idx
    keep.idx <- integer(0L)

    # remove not-needed measurement models
    for(g in 1:nblocks) {

        # higher-order factor loadings
        fac.idx <- which(PT$op == "=~" & PT$block == block.values[g] &
                         PT$lhs %in% lavpta$vnames$lv.regular[[g]] &
                         PT$rhs %in% lavpta$vnames$lv.regular[[g]])

        # eqs.names
        eqs.names <- unique( c(lavpta$vnames$eqs.x[[g]],
                               lavpta$vnames$eqs.y[[g]]) )
        all.names <- unique( c(eqs.names,
                               lavpta$vnames$lv.regular[[g]]) )

        # regressions
        reg.idx <- which(PT$op == "~" & PT$block == block.values[g] &
                         PT$lhs %in% eqs.names &
                         PT$rhs %in% eqs.names)

        # the variances
        var.idx <- which(PT$op == "~~" & PT$block == block.values[g] &
                         PT$lhs %in% all.names &
                         PT$rhs %in% all.names &
                         PT$lhs == PT$rhs)

        # optionally covariances (exo!)
        cov.idx <- which(PT$op == "~~" & PT$block == block.values[g] &
                         PT$lhs %in% all.names &
                         PT$rhs %in% all.names &
                         PT$lhs != PT$rhs)

        # means/intercepts
        int.idx <- which(PT$op == "~1" & PT$block == block.values[g] &
                         PT$lhs %in% all.names)

        keep.idx <- c(keep.idx, reg.idx, var.idx, cov.idx, int.idx,
                      fac.idx)

        # FIXME: ==, :=, <, >, == involving IND...

        # `simple' == constraints (simple lhs and rhs)
        #EQ.idx <- which(PT$op == "==" &
        #                PT$lhs %in% IND.plabel &
        #                PT$rhs %in% IND.plabel)

        con.idx <- which(PT$op %in% c("==","<",">",":="))
        if(length(con.idx) > 0L) {
            ID <- lav_partable_constraints_label_id(PT, def = TRUE)
            LABEL <- names(ID)
            con.keep <- logical( length(con.idx) )
            for(con in seq_len(length(con.idx))) {

                lhs.keep <- FALSE
                rhs.keep <- FALSE

                if(PT[con.idx[con],"op"] == ":=") {
                    lhs.keep <- TRUE
                } else {

                    # lhs
                    LHS.labels <- all.vars(as.formula(paste("~",
                                           PT[con.idx[con],"lhs"])))
                    if(length(LHS.labels) > 0L) {
                        # par id
                        LHS.freeid <- ID[match(LHS.labels, LABEL)]

                        # keep?
                        if(all(LHS.freeid %in% PT$free[keep.idx])) {
                            lhs.keep <- TRUE
                        }
                    } else {
                        lhs.keep <- TRUE
                    }
                }

                # rhs
                RHS.labels <- all.vars(as.formula(paste("~",
                                       PT[con.idx[con],"rhs"])))
                if(length(RHS.labels) > 0L) {
                    # par id
                    RHS.freeid <- ID[match(RHS.labels, LABEL)]

                    # keep?
                    if(all(RHS.freeid %in% PT$free[keep.idx])) {
                        rhs.keep <- TRUE
                    }
                } else {
                    rhs.keep <- TRUE
                }

                if(lhs.keep && rhs.keep) {
                    con.keep[con] <- TRUE
                }
            }

            EQ.idx <- con.idx[ con.keep ]
            keep.idx <- c(keep.idx, EQ.idx)
        } # con

    }

    if(idx.only) {
        return(keep.idx)
    }

    PT <- PT[keep.idx, , drop = FALSE]

    # clean up
    PT <- lav_partable_complete(PT)

    if(add.idx) {
        attr(PT, "idx") <- keep.idx
    }

    PT
}

