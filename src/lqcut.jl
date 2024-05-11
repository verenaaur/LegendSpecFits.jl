"""
    lq_drift_time_correction(lq_norm::Vector{Float64}, tdrift, e_cal; DEP_left=1589u"keV", DEP_right=1596u"keV")

Perform the drift time correction on the LQ data using the DEP peak. The function cuts outliers in lq and drift time, then performs a linear fit on the remaining data. The data is Corrected by subtracting the linear fit from the lq data.
# Returns
    * `result`: NamedTuple of the corrected lq data, the box used for the linear fit and the drift time function
    * `report`: NamedTuple of the histograms used for the fit
"""
function lq_drift_time_correction(lq_norm::Vector{Float64}, tdrift, e_cal; DEP_left=1589u"keV", DEP_right=1596u"keV", lower_exclusion=0.005, upper_exclusion=0.98, drift_cutoff_sgima=2.0)

    #Using fixed values for DEP, can be changed to use values from DEP fit from Energy calibration 
    lq_DEP_dt = lq_norm[DEP_left .< e_cal .< DEP_right]
    t_tcal = ustrip.(tdrift[DEP_left .< e_cal .< DEP_right])

    #lq cutoff
    #sort array to exclude outliers
    sort_lq = sort(lq_DEP_dt)
    low_cut = Int(round(length(sort_lq) * lower_exclusion)) # cut lower 0.5%
    high_cut = Int(round(length(sort_lq) * upper_exclusion)) # cut upper 2%
    lq_prehist = fit(Histogram, lq_DEP_dt, range(sort_lq[low_cut], sort_lq[high_cut], length=100))
    lq_prestats = estimate_single_peak_stats(lq_prehist)
    lq_start = lq_prestats.peak_pos - 3*lq_prestats.peak_sigma
    lq_stop = lq_prestats.peak_pos + 3*lq_prestats.peak_sigma

    lq_edges = range(lq_start, stop=lq_stop, length=51) 
    lq_hist_DEP = fit(Histogram, lq_DEP_dt, lq_edges)

    lq_DEP_stats = estimate_single_peak_stats(lq_hist_DEP)
    lq_result, lq_report = LegendSpecFits.fit_binned_gauss(lq_hist_DEP, lq_DEP_stats)
    µ_lq = mvalue(lq_result.μ)
    σ_lq = mvalue(lq_result.σ)

    #t_tcal cutoff
    drift_prehist = fit(Histogram, t_tcal, range(minimum(t_tcal), stop=maximum(t_tcal), length=100))
    drift_prestats = estimate_single_peak_stats(drift_prehist)
    drift_start = drift_prestats.peak_pos - 3*drift_prestats.peak_sigma
    drift_stop = drift_prestats.peak_pos + 3*drift_prestats.peak_sigma
    
    drift_edges = range(drift_start, stop=drift_stop, length=71)
    drift_hist_DEP = fit(Histogram, t_tcal, drift_edges)
    
    drift_DEP_stats = estimate_single_peak_stats(drift_hist_DEP)
    drift_result, drift_report = LegendSpecFits.fit_binned_gauss(drift_hist_DEP, drift_DEP_stats)
    µ_t = mvalue(drift_result.μ)
    σ_t = mvalue(drift_result.σ)

    #create box 
    box = (
    lq_lower = µ_lq - drift_cutoff_sgima * σ_lq, 
    lq_upper = µ_lq + drift_cutoff_sgima * σ_lq, 
    t_lower = µ_t - drift_cutoff_sgima * σ_t, 
    t_upper = µ_t + drift_cutoff_sgima * σ_t
    )

    #cut data according to box
    lq_box = lq_DEP_dt[box.lq_lower .< lq_DEP_dt .< box.lq_upper .&& box.t_lower .< t_tcal .< box.t_upper]
    t_box = t_tcal[box.lq_lower .< lq_DEP_dt .< box.lq_upper .&& box.t_lower .< t_tcal .< box.t_upper]

    #linear fit
    result_µ, report_µ = chi2fit(1, t_box, lq_box; uncertainty=true)
    parameters = mvalue(result_µ.par)
    drift_time_func(x) = parameters[2] .* x .+ parameters[1] 

    lq_classifier = lq_norm .- drift_time_func(ustrip.(tdrift))

    result = (
    lq_classifier = lq_classifier, 
    lq_box = box, 
    drift_time_func = drift_time_func
    )

    report = (
    lq_prehist = lq_prehist, 
    lq_report = lq_report, 
    drift_prehist = drift_prehist, 
    drift_report = drift_report
    )
    

    return result, report
end
export lq_drift_time_correction

"""
    LQ_cut(DEP_µ, DEP_σ, e_cal, lq_classifier)

Evaluates the cutoff value for the LQ cut. The function performs a binned gaussian fit on the sidebandsubtracted LQ histogram and evaluates the cutoff value difined at 3σ of the fit.
# Returns
    * `result`: NamedTuple of the cutoff value and the fit result
    * `report`: NamedTuple of the histograms used for the fit
"""
function LQ_cut(DEP_µ, DEP_σ, e_cal, lq_classifier; lower_exclusion=0.005, upper_exclusion=0.98, cut_sigma=3.0)
    # Define sidebands
    lq_DEP = lq_classifier[DEP_µ - 4.5 * DEP_σ .< e_cal .< DEP_µ + 4.5 * DEP_σ]
    lq_sb1 = lq_classifier[DEP_µ -  2 * 4.5 * DEP_σ .< e_cal .< DEP_µ - 4.5 * DEP_σ]
    lq_sb2 = lq_classifier[DEP_µ + 4.5 * DEP_σ .< e_cal .< DEP_µ + 2 * 4.5 * DEP_σ]
    
    # Generate values for histogram edges
    #exclude outliers
    sort_lq = sort(lq_DEP)
    low_cut = Int(round(length(sort_lq) * lower_exclusion)) # cut lower 0.5%
    high_cut = Int(round(length(sort_lq) * upper_exclusion)) # cut upper 2%
    prehist = fit(Histogram, lq_DEP, range(sort_lq[low_cut], sort_lq[high_cut], length=100))
    prestats = estimate_single_peak_stats(prehist)
    start = prestats.peak_pos - 3*prestats.peak_sigma
    stop = prestats.peak_pos + 3*prestats.peak_sigma
    edges = range(start, stop=stop, length=71) 

    # Create histograms with the same bin edges
    hist_DEP = fit(Histogram, lq_DEP, edges)
    hist_sb1 = fit(Histogram, lq_sb1, edges)
    hist_sb2 = fit(Histogram, lq_sb2, edges)
    
    # Subtract histograms
    weights_subtracted = hist_DEP.weights - hist_sb1.weights - hist_sb2.weights
    hist_subtracted = Histogram(edges, weights_subtracted)

    # Replace negative bins with 0
    weights_corrected = max.(weights_subtracted, 0)
    hist_corrected = Histogram(edges, weights_corrected)
    
    # Create a named tuple of temporary histograms for crosschecks
    temp_hists = (prehist = prehist, hist_DEP = hist_DEP, hist_sb1 = hist_sb1, hist_sb2 = hist_sb2, hist_subtracted = hist_subtracted, hist_corrected = hist_corrected)

    lq_DEP_stats = estimate_single_peak_stats(hist_corrected)
    fit_result, fit_report = fit_binned_gauss(hist_corrected, lq_DEP_stats)
    #final cutoff value
    cut_3σ = fit_result.μ + cut_sigma * fit_result.σ

    result = (
        cut = cut_3σ,
        fit_result = fit_result,
    )

    report = (
        temp_hists = temp_hists,
        fit_report = fit_report,
    )

    return result, report
end
export LQ_cut