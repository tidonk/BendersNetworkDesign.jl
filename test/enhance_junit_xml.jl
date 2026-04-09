"""
Enhance JUnit XML test reports with better metadata.

Transforms TestReports.jl output into a cleaner structure:
- Suite: Test categorization (unit, integration, feature)
- Name: Descriptive test name
- Classname: Source file path
- System-out: Detailed description and assertion
"""

using EzXML

# Mapping from test set names to categories and files
const TEST_METADATA = Dict(
    "Settings Tests" => (suite="Unit", file="test/runtests.jl", desc="Configuration loading and validation"),
    "SNDlib Reader Tests" => (suite="Unit", file="test/runtests.jl", desc="Network data structure parsing"),
    "Benders with Cut Limits" => (suite="Feature", file="test/test_benders_cut_limit.jl", desc="Benders decomposition with cut generation limits"),
    "Adaptive Mechanism" => (suite="Feature", file="test/test_adaptive_phase.jl", desc="Adaptive subproblem selection strategy"),
    "Benders vs Compact" => (suite="Integration", file="test/test_benders_vs_compact.jl", desc="Equivalence between Benders and compact formulations"),
    "Known Optimal Values" => (suite="Integration", file="test/test_known_objectives.jl", desc="Verification against known benchmark solutions"),
    "ML Training and Testing" => (suite="Feature", file="test/test_ml_train_and_test.jl", desc="Machine learning model training and prediction pipeline"),
    "Oracle Recording and Replay" => (suite="Feature", file="test/test_oracle.jl", desc="Deterministic scenario selection via oracle"),
)

# Mapping for specific test names to make them more readable
const TEST_NAME_MAPPINGS = Dict(
    "isfile(network_file)" => "Network file exists and is readable",
    r"result.*\.status == (MOI\.)?OPTIMAL" => "Optimization terminates with optimal status",
    r"abs\(.*_obj - .*_obj\) < \d+\.?\d*" => "Objective values match within tolerance",
    r"settings\.(\w+) isa (\w+)" => s"Setting '\1' has correct type (\2)",
    r"node\.(\w+) == " => s"Node property '\1' is correctly parsed",
)

function extract_test_category(testset_name::String)
    # Try to find the main category (before the first nested /)
    parts = split(testset_name, "/")
    
    # Skip "All Tests" root
    if length(parts) > 1 && parts[1] == "All Tests"
        parts = parts[2:end]
    end
    
    # Return the main category
    return parts[1]
end

function get_descriptive_name(assertion::String)
    # Try to make the assertion more readable
    for (pattern, replacement) in TEST_NAME_MAPPINGS
        if pattern isa Regex
            if occursin(pattern, assertion)
                return replace(assertion, pattern => replacement)
            end
        elseif assertion == pattern
            return replacement
        end
    end
    
    # Default: clean up the assertion string
    name = assertion
    name = replace(name, "&quot;" => "\"")
    name = replace(name, "&lt;" => "<")
    name = replace(name, "&gt;" => ">")
    name = replace(name, r"^(.{80}).*$" => s"\1...")  # Truncate if too long
    
    return name
end

function enhance_junit_xml(input_file::String, output_file::String)
    doc = readxml(input_file)
    root = doc.root
    
    # Process each testsuite
    for testsuite in eachelement(root)
        if nodename(testsuite) != "testsuite"
            continue
        end
        
        # Extract the test category from the suite name
        suite_name = testsuite["name"]
        category = extract_test_category(suite_name)
        
        # Get metadata for this category
        metadata = get(TEST_METADATA, category, (suite="Other", file="test/runtests.jl", desc=""))
        
        # Update testsuite attributes
        testsuite["name"] = metadata.suite
        
        # Process each testcase
        for testcase in eachelement(testsuite)
            if nodename(testcase) != "testcase"
                continue
            end
            
            # Get original test name (assertion)
            original_name = testcase["name"]
            
            # Create descriptive name
            descriptive_name = get_descriptive_name(original_name)
            
            # Update testcase attributes
            testcase["name"] = descriptive_name
            testcase["classname"] = metadata.file
            
            # Add system-out with details
            details = String[]
            
            if !isempty(metadata.desc)
                push!(details, "Test Category: $(metadata.desc)")
            end
            push!(details, "Assertion: $original_name")
            
            # Add as system-out element
            link!(testcase, ElementNode("system-out"))
            system_out_node = lastelement(testcase)
            link!(system_out_node, TextNode(join(details, "\n")))
        end
    end
    
    # Write enhanced XML
    write(output_file, doc)
    println("✓ Enhanced JUnit XML written to: $output_file")
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    input_file = get(ARGS, 1, "testlog.xml")
    output_file = get(ARGS, 2, "testlog_enhanced.xml")
    
    if !isfile(input_file)
        error("Input file not found: $input_file")
    end
    
    enhance_junit_xml(input_file, output_file)
    
    # Replace original if no output specified
    if output_file == "testlog_enhanced.xml"
        mv(output_file, input_file; force=true)
        println("✓ Original testlog.xml updated with enhanced metadata")
    end
end
