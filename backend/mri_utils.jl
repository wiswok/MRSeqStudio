include("Sequences.jl")

"Convert a json string containing sequence information into a KomaMRIBase.Sequence object"
json_to_sequence(json_seq::JSON3.Object, sys::Scanner) = begin
   vars = read_variables(json_seq["variables"])

   global seq = Sequence()
   
   N_x = 0

   blocks = json_seq["blocks"]
   iterators = read_iterators(blocks)

   function get_gradients(block::JSON3.Object)
      gradients = block["gradients"]
      GR = reshape([Grad(0,0) for i in 1:3],(3,1))
      for grad in gradients
         axis        = grad["axis"]
         delay       = eval_string(grad["delay"], vars, iterators)
         rise        = eval_string(grad["rise"], vars, iterators)
         flatTopTime = eval_string(grad["flatTop"], vars, iterators)
         amplitude   = eval_string(grad["amplitude"], vars, iterators)

         idx = axis == "x" ? 1 :
               axis == "y" ? 2 :
               axis == "z" ? 3 : 
               -1

         if amplitude > sys.Gmax
            error("G=$(amplitude) mT/m exceeds Gmax=$(sys.Gmax) mT/m")
         elseif amplitude/rise > sys.Smax
            error("Slew rate=$(amplitude/rise) mT/m/ms exceeds Smax=$(sys.Smax) mT/m/ms")
         end

         GR[idx] = Grad(amplitude, flatTopTime, rise, delay)
      end
      return GR
   end

   function isChild(index::Int)
      for i in eachindex(blocks)
         children = blocks[i]["children"]
         for j in eachindex(children)
            if children[j].number == (index - 1)
               return true
            end
         end
      end
      return false
   end

   function addToSeq(block::JSON3.Object) 
      if block["cod"] == 0          # <------------- Group
         iterator    =  block["iterator"]
         repetitions =  eval_string(block["repetitions"], vars, iterators)
         children =     block["children"]
         for i in 0:(repetitions-1)
            for j in eachindex(children)
               addToSeq(blocks[children[j].number+1])
            end
            iterators[iterator] += 1
         end

      elseif block["cod"] == 1       # <-------------------------- Excitation
         # print("Excitation\n")

         rf     = block["rf"][1]
         shape  = rf["shape"]
         deltaf = eval_string(rf["deltaf"], vars, iterators)

         # Flip angle and duration
         if haskey(block, "duration") & haskey(rf, "flipAngle")
            duration = eval_string(block["duration"], vars, iterators)
            flipAngle = eval_string(rf["flipAngle"], vars, iterators)

            aux_amplitude = 1e-6
            # 1. Rectangle (hard)
            if shape == 0
               AUX = PulseDesigner.RF_hard(aux_amplitude, duration, sys)
            # 2. Sinc
            elseif shape == 1
               AUX = PulseDesigner.RF_sinc(aux_amplitude, duration, sys)
            end

            amplitude = aux_amplitude * (flipAngle/get_flip_angles(AUX)[1])

         # Amplitude and duration
         elseif haskey(block, "duration") & haskey(rf, "b1Module")
            duration = eval_string(block["duration"], vars, iterators)  
            amplitude = eval_string(rf["b1Module"], vars, iterators)
        
         # Flip angle and amplitude
         elseif haskey(rf, "flipAngle") & haskey(rf, "b1Module")
            flipAngle = eval_string(rf["flipAngle"], vars, iterators)
            amplitude = eval_string(rf["b1Module"], vars, iterators)

            aux_duration = 1e-3
            # 1. Rectangle (hard)
            if shape == 0
               AUX = PulseDesigner.RF_hard(amplitude, aux_duration, sys)
            # 2. Sinc
            elseif shape == 1
               AUX = PulseDesigner.RF_sinc(amplitude, aux_duration, sys)
            end

            duration = aux_duration * (flipAngle/get_flip_angles(AUX)[1])
         end

         # 1. Rectangle (hard)
         if shape == 0
            EX = PulseDesigner.RF_hard(amplitude, duration, sys; Δf=deltaf)
         # 2. Sinc
         elseif shape == 1
            EX = PulseDesigner.RF_sinc(amplitude, duration, sys; Δf=deltaf)[1]
         end

         EX.GR = get_gradients(block)
         EX.RF[1].delay = maximum(EX.GR.rise)
         EX.DUR[1] = EX.RF[1].delay + max(maximum(EX.GR.T .+ EX.GR.fall), duration)
         seq += EX

      elseif block["cod"] == 2       # <-------------------------- Delay
         # print("Delay\n")

         duration = eval_string(block["duration"], vars, iterators)
         DELAY = Delay(duration)
         seq += DELAY

      elseif block["cod"] in [3,4]   # <-------------------------- Dephase or Readout
         if block["cod"] == 3
            # print("Dephase\n")
         elseif block["cod"] == 4
            # print("Readout\n")
         end

         DEPHASE = Sequence(get_gradients(block))

         if block["cod"] == 4
            DEPHASE.ADC[1].N = eval_string(block["samples"], vars, iterators)
            DEPHASE.ADC[1].T = eval_string(block["duration"], vars, iterators)
            DEPHASE.ADC[1].delay = eval_string(block["adcDelay"], vars, iterators)
            DEPHASE.ADC[1].ϕ = eval_string(block["adcPhase"], vars, iterators)

            N_x = eval_string(block["samples"], vars, iterators)
         end

         seq += DEPHASE

      elseif block["cod"] == 5       # <-------------------------- EPI
         # print("EPI\n")

         fov = eval_string(block["fov"], vars, iterators)
         lines = eval_string(block["lines"], vars, iterators)
         samples = eval_string(block["samples"], vars, iterators)

         N_x = eval_string(block["samples"], vars, iterators)

         epi = EPI(fov, lines, sys)

         seq += epi

      elseif block["cod"] == 6       # <-------------------------- GRE  
         # print("GRE\n")

         fov = eval_string(block["fov"], vars, iterators)
         lines = eval_string(block["lines"], vars, iterators)
         samples = eval_string(block["samples"], vars, iterators)

         t  = block["t"][1]
         te = eval_string(t["te"], vars, iterators)
         tr = eval_string(t["tr"], vars, iterators)

         rf    = block["rf"][1]
         α     = eval_string(rf["flipAngle"], vars, iterators)
         Δf    = eval_string(rf["deltaf"], vars, iterators)

         seq += GRE(fov, lines, te, tr, α, sys; Δf=Δf)
      end 
   end

   for i in eachindex(blocks)
      if !isChild(i)
         addToSeq(blocks[i])
      end
   end

   seq.DEF = Dict("Nx"=>N_x,"Ny"=>N_x,"Nz"=>1)

   display(seq)
   return seq
end

"Convert a json string containing scanner information into a KomaMRIBase.Scanner object"
json_to_scanner(json_scanner::JSON3.Object) = begin
   vars = read_variables(json_scanner["variables"])
   parameters = json_scanner["parameters"]

   sys = Scanner(
      B0 = eval_string(parameters["b0"], vars),
      B1 = eval_string(parameters["b1"], vars),
      Gmax = eval_string(parameters["gmax"], vars),
      Smax = eval_string(parameters["smax"], vars),
      ADC_Δt = eval_string(parameters["deltat"], vars),
   )
   
   return sys
end

"Obtain the reconstructed image from raw_signal (obtained from simulation)"
recon(raw_signal, seq) = begin
   recParams = Dict{Symbol,Any}(:reco=>"direct")
   Nx = seq.DEF["Nx"]
   Ny = seq.DEF["Ny"]

   recParams[:reconSize] = (Nx, Ny)
   recParams[:densityWeighting] = false

   acqData = AcquisitionData(raw_signal)
   acqData.traj[1].circular = false #Removing circular window
   acqData.traj[1].nodes = acqData.traj[1].nodes[1:2,:] ./ maximum(2*abs.(acqData.traj[1].nodes[:])) #Normalize k-space to -.5 to .5 for NUFFT

   aux = @timed reconstruction(acqData, recParams)
   image  = reshape(aux.value.data,Nx,Ny,:)
   kspace = KomaMRI.fftc(reshape(aux.value.data,Nx,Ny,:))

   return image, kspace
end

"Obtain raw RM signal. Input arguments are a 2D matrix (sequence) and a 1D vector (system parameters)"
sim(phantom, sequence_json, scanner_json, path) = begin
   # Scanner
   sys = json_to_scanner(scanner_json)

   # Sequence
   seq = json_to_sequence(sequence_json, sys)

   # Simulation parameters
   simParams = Dict{String,Any}()

   # Simulation
   raw_signal = 0
   try
      raw_signal = simulate(phantom, seq, sys; sim_params=simParams, w=path)
   catch e
      println("Simulation failed")
      display(e)
      update_progress!(path, -2)
      return e
   end

   # Reconstruction
   try
      image, kspace = recon(raw_signal, seq)
      update_progress!(path, 101)
      return image
   catch e
      println("Reconstruction failed")
      display(e)
      update_progress!(path, -2)
      return e
   end
end

function read_variables(json_variables::JSON3.Array)
   variables = Dict{String,Any}()
   for variable in json_variables
      variables[variable["name"]] = variable["value"]
   end
   return variables
end

function read_iterators(json_blocks::JSON3.Array)
   iterators = Dict{String,Int}()
   for block in json_blocks
      if block["cod"] == 0 # Group
         iterators[block["iterator"]] = 0 # Initialize iterator
      end
   end
   return iterators
end

"Eval a string expression and return the result"
function eval_string(expr::String, variables::Dict, iterators::Dict{String,Int}=Dict{String,Int}())
   if expr == ""
       return 0
   end

   allowed_operators = Set(["+", "-", "*", "/", "(", ")", "^"])
   number_pattern = r"^\d+\.?\d*(?:[eE][+-]?\d+)?$"
   identifier_pattern = r"^[a-zA-Z_][a-zA-Z0-9_]*$"

   tokens = eachmatch(r"[a-zA-Z_][a-zA-Z0-9_]*|\d+\.?\d*(?:[eE][+-]?\d+)?|[()+\-*/^]", expr)

   all_vars = merge(variables, iterators, Dict("pi" => pi))

   rebuilt = String[]
   for token in tokens
      val = token.match
      if val in allowed_operators || occursin(number_pattern, val)
         push!(rebuilt, val)
      elseif occursin(identifier_pattern, val) && haskey(all_vars, val)
         push!(rebuilt, string(all_vars[val]))
      else
         error("Symbol not recognized: '$val'")
      end
   end

   safe_expr = join(rebuilt, " ")
   try
      result = eval(Meta.parse(safe_expr))
      return result
   catch err
      error("Error evaluating expression: $(err)")
   end
end