function get_aoe_standard_pseudo_prior(h::Histogram, ps::NamedTuple, fit_func::Symbol; fixed_position::Bool=false)
    if fit_func == :aoe_one_bck
        pprior_base = NamedTupleDist(
            μ = ifelse(fixed_position, ConstValueDist(ps.peak_pos), Normal(ps.peak_pos, 0.5*ps.peak_sigma)),
            σ = weibull_from_mx(ps.peak_sigma, 2*ps.peak_sigma),
            n = LogUniform(0.01*ps.peak_counts, 5*ps.peak_counts),
            B = LogUniform(0.1*ps.mean_background, 10*ps.mean_background),
            δ = LogUniform(0.001, 10.0)
        )
    elseif fit_func == :aoe_two_bck
        pprior_base = NamedTupleDist(
            μ = Normal(ps.peak_pos, ps.peak_sigma/6),
            σ = Normal(ps.peak_sigma, ps.peak_sigma/6),
            n = LogNormal(log(ps.peak_counts), 1.0),
            B = Normal(ps.mean_background, 0.2*ps.mean_background/3),
            δ = weibull_from_mx(0.1, 0.8),
            μ2 = Normal(-15, 5),
            σ2 = LogNormal(log(10), 0.5),
            B2 = Normal(ps.mean_background, 0.2*ps.mean_background/3),
            δ2 = LogNormal(log(10), 1)
        )
    else
        throw(ArgumentError("fit_func $fit_func not supported for aoe peakshapes"))
    end
    return pprior_base
end

function get_aoe_pseudo_prior(h::Histogram, ps::NamedTuple, fit_func::Symbol; pseudo_prior::NamedTupleDist=NamedTupleDist(empty = true), kwargs...)
    standard_pseudo_prior = get_aoe_standard_pseudo_prior(h, ps, fit_func; kwargs...)
    # use standard priors in case of no overwrites given
    if !(:empty in keys(pseudo_prior))
        # check if input overwrite prior has the same fields as the standard prior set
        @assert all(f -> f in keys(standard_pseudo_prior), keys(pseudo_prior)) "Pseudo priors can only have $(keys(standard_pseudo_prior)) as fields."
        # replace standard priors with overwrites
        pseudo_prior = merge(standard_pseudo_prior, pseudo_prior)
    else
        # take standard priors as pseudo priors with overwrites
        pseudo_prior = standard_pseudo_prior    
    end
    return pseudo_prior
end