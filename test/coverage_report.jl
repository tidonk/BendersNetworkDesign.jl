#!/usr/bin/env julia
using Coverage

coverage = process_folder("src")
covered, total = get_summary(coverage)

println("\n╔══════════════════════════════════════════════════════════════════════╗")
println("║                      CODE COVERAGE REPORT                            ║")
println("╚══════════════════════════════════════════════════════════════════════╝\n")

# Process all files
for file in coverage
    fname = basename(file.filename)
    
    # Calculate coverage percentage from source_lines and coverage arrays
    if file.coverage !== nothing && length(file.coverage) > 0
        covered_in_file = count(x -> x !== nothing && x > 0, file.coverage)
        total_in_file = length(file.coverage)
        cov_pct = total_in_file > 0 ? 100.0 * covered_in_file / total_in_file : 0.0
    else
        cov_pct = 0.0
    end
    
    # Calculate bar (20 characters wide)
    bars = round(Int, cov_pct / 5)
    bar_str = "█" ^ bars * "░" ^ (20 - bars)
    
    # Format line
    pad_len = 45 - length(fname)
    println(fname * repeat(" ", max(0, pad_len)) * " " * bar_str * " " * lpad(string(round(cov_pct, digits=1)) * "%", 6))
end

println("\n" * "─"^70)
println("TOTAL COVERAGE: $covered/$total lines = $(round(100*covered/total, digits=2))%")
println("─"^70)

# Generate LCOV report for external tools
LCOV.writefile("coverage.lcov", coverage)
println("\n✓ LCOV report written to: coverage.lcov")

# Generate Cobertura XML for GitLab Test Coverage Visualization
function generate_cobertura_xml(coverage_data, output_file="coverage.xml")
    cov_covered, cov_total = get_summary(coverage_data)
    
    open(output_file, "w") do io
        println(io, "<?xml version=\"1.0\" ?>")
        println(io, "<coverage version=\"1.0\" timestamp=\"$(time())\" line-rate=\"$(cov_covered/cov_total)\" branch-rate=\"0.0\">")
        println(io, "  <sources>")
        println(io, "    <source>src</source>")
        println(io, "  </sources>")
        println(io, "  <packages>")
        println(io, "    <package name=\"BendersNetworkDesign\" line-rate=\"$(cov_covered/cov_total)\" branch-rate=\"0.0\" complexity=\"0.0\">")
        println(io, "      <classes>")
        
        for file in coverage_data
            rel_path = replace(file.filename, r"^.*src/" => "src/")
            file_covered = count(x -> x !== nothing && x > 0, file.coverage)
            file_total = length(file.coverage)
            file_rate = file_total > 0 ? file_covered / file_total : 0.0
            
            println(io, "        <class name=\"$(basename(file.filename))\" filename=\"$rel_path\" line-rate=\"$file_rate\" branch-rate=\"0.0\" complexity=\"0.0\">")
            println(io, "          <methods/>")
            println(io, "          <lines>")
            
            for (line_num, hits) in enumerate(file.coverage)
                if hits !== nothing
                    println(io, "            <line number=\"$line_num\" hits=\"$hits\"/>")
                end
            end
            
            println(io, "          </lines>")
            println(io, "        </class>")
        end
        
        println(io, "      </classes>")
        println(io, "    </package>")
        println(io, "  </packages>")
        println(io, "</coverage>")
    end
    
    println("✓ Cobertura XML written to: $output_file")
end

generate_cobertura_xml(coverage)
