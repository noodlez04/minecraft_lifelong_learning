local classic = require 'classic'
local signal = require 'posix.signal'
local Singleton = require 'structures/Singleton'
local Agent = require 'Agent'
local Display = require 'Display'
local Validation = require 'Validation'

local Master = classic.class('Master')

-- Sets up environment and agent
function Master:_init(opt)
  self.opt = opt
  self.verbose = opt.verbose
  self.learnStart = opt.learnStart
  self.progFreq = opt.progFreq
  self.autoSaveFreq = opt.autoSaveFreq
  self.reportWeights = opt.reportWeights
  self.noValidation = opt.noValidation
  self.valFreq = opt.valFreq
  self.experiments = opt.experiments
  self._id = opt._id
  self.numTasks = opt.numTasks
  self.task = opt.task
  self.freezeLayers = opt.freezeLayers

  -- Set up singleton global object for transferring step
  self.globals = Singleton({step = 1}) -- Initial step
  torch.save(paths.concat(opt.experiments, opt._id, 'metadata.t7'), opt)

  -- Initialise environment
  log.info('Setting up ' .. opt.env)
  local Env = require(opt.env)
  self.env = Env(opt) -- Environment instantiation

  -- Create DQN agent
  log.info('Creating DQN')
  local save_date = 0
  local autosave_date = 0
  local save_path = paths.concat(opt.experiments, opt._id, 'agent.t7')
  local autosave_path = paths.concat(opt.experiments, opt._id, 'agent_autosave.t7')
  if paths.filep(save_path) then
    save_date = tonumber(io.popen('stat -c %Y ' .. save_path):read())
  end
  if paths.filep(autosave_path) then
    autosave_date = tonumber(io.popen('stat -c %Y ' .. autosave_path):read())
  end
  if save_date ~= 0 or autosave_date ~= 0 then
    -- Ask to load saved agent if found in experiment folder (resuming training)
    log.info('Saved agent found - load (y/n)?')
    if io.read() == 'y' then
      -- Load the model which is more updated, among save and autosave)
      if save_date > autosave_date then
        log.info('Loading saved agent')
        self.agent = torch.load(save_path)
      else
        log.info('Loading autosaved agent')
        self.agent = torch.load(autosave_path)
      end
      if self.agent._id ~= opt._id then
        log.info('Renaming agent to ' .. opt._id)
        self.agent._id = opt._id
      end
      if not self.agent.scoreKeeper then
        self.agent:setScoreKeeper(opt)
        self.agent.optimParams.isFreq = opt.isFreq
      end
      if self.agent.optimParams.etaStart ~= opt.eta or
              self.agent.optimParams.lrDecay ~= opt.lrDecay or
              self.agent.optimParams.lrDecayFreq ~= opt.lrDecayFreq or
              self.agent.optimParams.etaFinal ~= opt.etaFinal then
        self.agent.optimParams.learningRate = opt.eta
        log.info('Updating eta to ' .. self.agent.optimParams.learningRate)
        self.agent.optimParams.etaFinal = opt.etaFinal
        self.agent.optimParams.etaStart = opt.learningRate
        self.agent.optimParams.lrDecay = opt.lrDecay
        self.agent.optimParams.lrDecayFreq = opt.lrDecayFreq
      end
      self.numTasks = self.agent.numTasks
      if self.task > self.numTasks then
        error('The agent has ' .. self.numTasks .. ' tasks, but task requested is ' .. self.task)
      end
      self.agent:switchTask(self.task)

      -- Reset globals (step) from agent
      Singleton.setInstance(self.agent.globals)
      self.globals = Singleton.getInstance()

      -- Switch saliency style
      self.agent:setSaliency(opt.saliency)
    else
      self.agent = Agent(opt)
      if paths.filep(opt.network) then
        -- Load saved agent if specified
        log.info('Loading pretrained network weights')
        self.agent:loadWeights(opt.network)
      end
    end
  else
    self.agent = Agent(opt)
    if paths.filep(opt.network) then
      -- Load saved agent if specified
      log.info('Loading pretrained network weights')
      self.agent:loadWeights(opt.network)
    end
  end
  self.agent:freeze(self.freezeLayers)

  -- Start gaming
  log.info('Starting ' .. opt.env)
  if opt.game ~= '' then
    log.info('Starting game: ' .. opt.game)
  end
  local state = self.env:start()

  -- Set up display (if available)
  self.hasDisplay = false
  if opt.displaySpec then
    self.hasDisplay = true
    self.display = Display(opt, self.env:getDisplay())
  end

  -- Set up validation (with display if available)
  self.validation = Validation(opt, self.agent, self.env, self.display)

  classic.strict(self)
end

-- Trains agent
function Master:train()
  log.info('Training mode')

  -- Catch CTRL-C to save
  self:catchSigInt()

  local reward, state, terminal = 0, self.env:start(), false

  -- Set environment and agent to training mode
  self.env:training()
  self.agent:training()

  -- Training variables (reported in verbose mode)
  local episode = 1
  local episodeScore = reward

  -- Training loop
  local initStep = self.globals.step -- Extract step
  local stepStrFormat = '%0' .. (math.floor(math.log10(self.opt.steps)) + 1) .. 'd' -- String format for padding step with zeros
  for step = initStep, self.opt.steps do
    self.globals.step = step -- Pass step number to globals for use in other modules

    -- Observe results of previous transition (r, s', terminal') and choose next action (index)
    local action = self.agent:observe(reward, state, terminal) -- As results received, learn in training mode
    if not terminal then
      -- Act on environment (to cause transition)
      reward, state, terminal = self.env:step(action)
      -- Track score
      episodeScore = episodeScore + reward
    else
      if self.verbose then
        -- Print score for episode
        log.info('Steps: ' .. string.format(stepStrFormat, step) .. '/' .. self.opt.steps .. ' | Episode ' .. episode .. ' | Score: ' .. episodeScore)
      end

      -- Start a new episode
      episode = episode + 1
      reward, state, terminal = 0, self.env:start(), false
      episodeScore = reward -- Reset episode score
    end

    -- Display (if available)
    if self.hasDisplay then
      self.display:display(self.agent, self.env:getDisplay())
    end

    -- Trigger learning after a while (wait to accumulate experience)
    if step == self.learnStart then
      log.info('Learning started')
    end

    -- Report progress
    if step % self.progFreq == 0 then
      log.info('Steps: ' .. string.format(stepStrFormat, step) .. '/' .. self.opt.steps)
      -- Report weight and weight gradient statistics
      if self.reportWeights then
        local reports = self.agent:report()
        for r = 1, #reports do
          log.info(reports[r])
        end
      end
    end

    -- Autosave intermediate training results, for case of crashes or disconnections
    if step % self.autoSaveFreq == 0 then
      log.info('Autosaving agent at step ' .. step .. '...')
      torch.save(paths.concat(self.experiments, self._id, 'agent_autosave.t7'), self.agent) -- Save agent to resume training
    end


    -- Validate
    if not self.noValidation and step >= self.learnStart and step % self.valFreq == 0 then
      self.validation:validate() -- Sets env and agent to evaluation mode and then back to training mode

      log.info('Resuming training')
      -- Start new game (as previous one was interrupted)
      reward, state, terminal = 0, self.env:start(), false
      episodeScore = reward
    end
  end

  log.info('Finished training')
end

function Master:evaluate()
  local currentEvaluation = self.opt.Tensor(self.validation:evaluate()) -- Sets env and agent to evaluation mode
  for i = 1, currentEvaluation:size(1) do
    if 0 >= currentEvaluation[i] and currentEvaluation[i] >= -25 then
      currentEvaluation[i] = currentEvaluation[i] + 1000
    end
  end
  print('Average score of evaluation: ' .. currentEvaluation:mean())
end

-- Sets up SIGINT (Ctrl+C) handler to save network before quitting
function Master:catchSigInt()
  signal.signal(signal.SIGINT, function(signum)
    log.warn('SIGINT received')
    log.info('Save agent (y/n)?')
    if io.read() == 'y' then
      log.info('Saving agent')
      torch.save(paths.concat(self.experiments, self._id, 'agent.t7'), self.agent) -- Save agent to resume training
    end
    log.warn('Exiting')
    os.exit(128 + signum)
  end)
end

return Master
