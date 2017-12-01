#!/bin/bash

th $DQNF/distill_main.lua -env DiscreteMinecraft -modelBody models.Minecraft -mode train -height 84 -width 84 -zoom 4 -valSteps 5000 -hiddenSize 256 -histLen 4 -bootstraps 0 -memSampleFreq 400 -memNSamples 100 -memSize 5e4 -learnStart 5e3 -epsilonSteps 5e4 -eta 0.003 -tau 1000 -rewardClip 0 -tdClip 0 -gradClip 0 -verbose true -progFreq 1e3 -reportWeights true -cudnn true -_id distilledAgent5 -x_min_limit -3 -x_max_limit 3 -z_min_limit -3 -z_max_limit 3 -steps 5e8 -mission_xml /home/deep1/Itai_Asaf/minecraft_lifelong_learning/missions/chickenFinder.discreteActions.bright.xml -findReward 1000 -commandReward -1 -timeReward 0 -roundTime 10000 -port 10000 -gamma 0.97 -valFreq 3e4 -duel false -numTasks 1 -batchSize 32
