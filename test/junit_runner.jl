"""
Custom JUnit XML test runner with enhanced metadata.

Generates JUnit XML with proper structure:
- Suite: Test categorization (unit, integration, feature)
- Name: Test description
- Filename: Source file containing the test
- System-out: Detailed description and assertion
"""

using Test
using EzXML

mutable struct TestResult
    suite::String
    name::String
    filename::String
    description::String
    assertion::String
    passed::Bool
    time::Float64
    error_message::Union{Nothing, String}
end

const TEST_RESULTS = TestResult[]
const CURRENT_SUITE = Ref{String}("")
const CURRENT_FILE = Ref{String}("")
const CURRENT_DESC = Ref{String}("")

"""
Set the current test suite category (unit, integration, feature, etc.)
"""
function set_test_suite(suite::String)
    CURRENT_SUITE[] = suite
end

"""
Set the current test file being executed
"""
function set_test_file(filename::String)
    CURRENT_FILE[] = filename
end

"""
Set description for the next group of tests
"""
function set_test_description(desc::String)
    CURRENT_DESC[] = desc
end

"""
Custom test macro that captures metadata
"""
macro test_with_metadata(name::String, assertion)
    return quote
        local start_time = time()
        local result = TestResult(
            CURRENT_SUITE[],
            $(esc(name)),
            CURRENT_FILE[],
            CURRENT_DESC[],
            $(string(assertion)),
            false,
            0.0,
            nothing
        )
        
        try
            @test $(esc(assertion))
            result.passed = true
        catch e
            result.passed = false
            result.error_message = sprint(showerror, e)
        end
        
        result.time = time() - start_time
        push!(TEST_RESULTS, result)
        result.passed
    end
end

"""
Generate JUnit XML from collected test results
"""
function generate_junit_xml(output_file::String="testlog.xml")
    doc = XMLDocument()
    
    # Group results by suite
    suites_dict = Dict{String, Vector{TestResult}}()
    for result in TEST_RESULTS
        suite_key = result.suite
        if !haskey(suites_dict, suite_key)
            suites_dict[suite_key] = TestResult[]
        end
        push!(suites_dict[suite_key], result)
    end
    
    # Calculate totals
    total_tests = length(TEST_RESULTS)
    total_failures = count(r -> !r.passed, TEST_RESULTS)
    total_errors = 0
    
    # Create root element
    testsuites = ElementNode("testsuites")
    testsuites["tests"] = string(total_tests)
    testsuites["failures"] = string(total_failures)
    testsuites["errors"] = string(total_errors)
    
    # Create testsuite for each category
    suite_id = 0
    for (suite_name, results) in suites_dict
        testsuite = ElementNode("testsuite")
        testsuite["name"] = suite_name
        testsuite["tests"] = string(length(results))
        testsuite["failures"] = string(count(r -> !r.passed, results))
        testsuite["errors"] = "0"
        testsuite["time"] = string(sum(r -> r.time, results))
        testsuite["timestamp"] = string(now())
        testsuite["hostname"] = gethostname()
        testsuite["id"] = string(suite_id)
        suite_id += 1
        
        # Add individual test cases
        for (idx, result) in enumerate(results)
            testcase = ElementNode("testcase")
            testcase["name"] = result.name
            testcase["id"] = string(idx)
            testcase["classname"] = result.filename
            testcase["time"] = string(result.time)
            
            # Add system-out with description and assertion
            if !isempty(result.description) || !isempty(result.assertion)
                system_out = ElementNode("system-out")
                details = String[]
                if !isempty(result.description)
                    push!(details, "Description: $(result.description)")
                end
                if !isempty(result.assertion)
                    push!(details, "Assertion: $(result.assertion)")
                end
                addelement!(system_out, TextNode(join(details, "\n")))
                addelement!(testcase, system_out)
            end
            
            # Add failure element if test failed
            if !result.passed
                failure = ElementNode("failure")
                failure["message"] = "Test failed"
                if result.error_message !== nothing
                    addelement!(failure, TextNode(result.error_message))
                end
                addelement!(testcase, failure)
            end
            
            addelement!(testsuite, testcase)
        end
        
        addelement!(testsuites, testsuite)
    end
    
    setroot!(doc, testsuites)
    write(output_file, doc)
    println("JUnit XML report written to: $output_file")
end

"""
Clear collected test results (useful for testing)
"""
function clear_test_results!()
    empty!(TEST_RESULTS)
end
