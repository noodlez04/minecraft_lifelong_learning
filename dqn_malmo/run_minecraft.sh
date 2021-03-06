#!/bin/bash

th main.lua -env Minecraft -modelBody models.Minecraft -mode train -height 84 -width 84 -zoom 4 -valSteps 5000 -hiddenSize 256 -recurrent true -histLen 4 -bootstraps 0 -memSampleFreq 400 -memNSamples 100 -memSize 5e4 -learnStart 5e3 -epsilonSteps 5e4 -eta 0.00025 -tau 1000 -rewardClip 0 -tdClip 0 -gradClip 0 -noValidation true -verbose true -progFreq 1e3 -reportWeights true -cudnn true -_id "coalTeacher.saveTest" -x_min_limit -4 -x_max_limit 4 -z_min_limit -4 -z_max_limit 4 -steps 50
