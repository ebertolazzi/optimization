classdef LinesearchMoreThuente < LinesearchForwardBackward
  %%
  %  Translation of minpack subroutine cvsrch
  %  based on matlab conversiuon by Dianne O'Leary July 1991
  %  original code by
  %
  %  by Jorge J. More' and David J. Thuente
  %  Argonne National Laboratory. MINPACK Project. June 1983
  %
  %  OO matlab version by Enrico Bertolazzi
  %
  %  The purpose of the linesearch is to find a step which satisfies
  %  a sufficient decrease condition and a curvature condition.
  %  The user must provide a subroutine which calculates the
  %  function and the gradient.
  %
  %  At each stage the method `search` updates an interval of
  %  uncertainty with enM.Dfoints LO.alpha and HI.alpha.
  %  The interval of uncertainty is initially chosen so that it
  %  contains a minimizer of the modified function
  %
  %    phi(alpha) = f(alpha) - f(0) - c1*alpha*f'(0)
  %
  %  If a step is obtained for which the modified function has a nonpositive
  %  function value and nonnegative derivative, then the interval of
  %  uncertainty is chosen so that it contains a minimizer of f(alpha).
  %
  %  The algorithm is designed to find a step which satisfies
  %  the sufficient decrease condition
  %
  %    f(alpha) <= f(0) + c1*alpha*f'(0),
  %
  %  and the curvature condition
  %
  %    | f'(alpha) | <= c2 * |f'(0)|
  %
  %  If c1 is less than c2 and if, for example, the function is bounded below,
  %  then there is always a step which satisfies both conditions.
  %  If no step can be found which satisfies both conditions, then the
  %  algorithm usually stops when rounding errors prevent further progress.
  %  In this case alpha only satisfies the sufficient decrease condition.
  %

  properties (SetAccess = private, Hidden = true)

    xtol % Linesearch termination occurs when the relative width
         % of the interval of uncertainty is at most xtol.

    info % an integer output variable set as follows:
         %
         % info = 0  Improper input parameters.
         %
         % info = 1  The sufficient decrease condition and the
         %           directional derivative condition hold.
         %
         % info = 2  Relative width of the interval of uncertainty
         %           is at most xtol.
         %
         % info = 3  Number of calls to fcn has reached max_fun_eval.
         %
         % info = 4  The step is at the lower bound alpha_min.
         %
         % info = 5  The step is at the upper bound alpha_max.
         %
         % info = 6  Rounding errors prevent further progress.
         %           There may not be a step which satisfies the
         %           sufficient decrease and curvature conditions.
         %           Tolerances may be too small.

    xtrapf

    step_min
    step_max

    f0_extra_epsi
  end

  methods (Hidden = true)
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %
    % minimum of a cubic closer to L
    %
    function alphac = minCubic( ~, L, R )
      dA    = R.alpha - L.alpha;
      theta = 3*(L.f - R.f)/dA + R.Df + L.Df;
      s     = max(abs([ theta, R.Df, L.Df ]));
      gamma = s*sqrt( (theta/s)^2 - (R.Df/s)*(L.Df/s) );
      if L.alpha > R.alpha
        gamma = -gamma;
      end
      p      = (gamma - L.Df) + theta;
      q      = ((gamma - L.Df) + gamma) + R.Df;
      r      = p/q;
      alphac = L.alpha + r*dA;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %
    % minimum of a quadratic interpolating L.f, L.Df, R.f
    %
    function alphaq = minQuadratic( ~, L, R )
      DX     = R.alpha - L.alpha;
      t      = 0.5*(L.Df/(L.Df+(L.f - R.f)/DX));
      alphaq = L.alpha + t*DX;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %
    % minimum of a quadratic interpolating L.f, L.Df, R.Df
    %
    function alphaq = minQuadratic2( ~, L, R )
      DX     = R.alpha - L.alpha;
      t      = L.Df/(L.Df-R.Df);
      alphaq = L.alpha + t*DX;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    %
    % minimum of a quadratic interpolating L.f, L.Df, R.Df
    %
    function ok = isMonotonic( ~, L, R )
      DFDX = (R.f - L.f)/(R.alpha - L.alpha);
      ok   = (L.Df^2+R.Df^2+L.Df*R.Df)+9*DFDX^2-6*(L.Df+R.Df)*DFDX < 0;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    function [LO, HI, alphaf, bracketed, info] = ...
      safeguardedStep( self, LO, HI, M, bracketed, step_maxmax )
      %
      % The purpose of safeguardedStep is to compute a safeguarded step for
      % a linesearch and to update an interval of uncertainty for
      % a minimizer of the function.
      %
      % The struct LO contains the step with the least function value.
      % The struct M contains the current step.
      % It is assumed that the derivative at LO is negative in the
      % direction of the step.
      % If bracketed is set true then a minimizer has been bracketed in an
      % interval of uncertainty with endpoints LO.alpha and HI.alpha.
      %
      % LO specify the step at the best step obtained so far.
      % The derivative must be negative in the direction of the step,
      % that is, LO.Df and (M.alpha-LO.alpha) must have opposite signs.
      % On output these parameters are updated appropriately.
      %
      % HI specify the step at the other endpoint of the interval of
      % uncertainty. On output these parameters are updated appropriately.
      %
      % struct M specify the current step.
      % If bracketed is set true then on input M.alpha must be between
      % LO.alpha and HI.alpha. On output M.alpha is set to the new step.
      %
      % bracketed is a logical variable which specifies if a minimizer
      % has been bracketed. If the minimizer has not been bracketed
      % then on input bracketed must be set false.
      % If the minimizer is bracketed then on output bracketed is set true.
      %
      % info is an integer output variable set as follows:
      % If info = 1,2,3,4,5 then the step has been computed according
      % to one of the six cases below.
      % Otherwise info = 0, and this indicates improper input parameters.
      %
      % Check the input parameters for errors.
      aL     = min( LO.alpha, HI.alpha );
      aR     = max( LO.alpha, HI.alpha );
      alphaf = 0;
      if bracketed
        if M.alpha <= aL || M.alpha >= aR
          info = 0;
          return;
        end
      end
      DX = M.alpha - LO.alpha;
      if LO.Df*DX >= 0
        info = 0;
        return;
      end
      %
      % Determine if the derivatives have opposite sign.
      %
      sgnd = sign(M.Df*LO.Df);
      %
      % First case.
      % A higher function value. The minimum is bracketed.
      % If the cubic step is closer to LO.alpha than the quadratic step,
      % the cubic step is taken, else the average of the cubic and
      % quadratic steps is taken.
      %
      if M.f > LO.f
        info   = 1;
        bound  = true;
        alphac = self.minCubic( LO, M );
        alphaq = self.minQuadratic( LO, M );
        if abs(alphac-LO.alpha) < abs(alphaq-LO.alpha)
          alphaf = alphac;
        else
          alphaf = alphac + (alphaq - alphac)/2;
        end
        bracketed = true;
      elseif sgnd < 0
        %
        % Second case.
        % A lower function value and derivatives of opposite sign.
        % The minimum is bracketed. If the cubic step is closer to LO.alpha
        % than the quadratic (secant) step, the cubic step is taken,
        % else the quadratic step is taken.
        %
        info  = 2;
        bound = false;
        alphac = self.minCubic( M, LO );
        alphas = self.minQuadratic2( M, LO );
        if abs(alphac-M.alpha) > abs(alphas-M.alpha)
          alphaf = alphac;
        else
          alphaf = alphas;
        end
        bracketed = true;
      elseif abs(M.Df) < abs(LO.Df)
        %
        % Third case.
        % A lower function value, derivatives of the same sign, and the
        % magnitude of the derivative decreases.
        % The cubic step is only used if the cubic tends to infinity in the
        % direction of the step or if the minimum of the cubic is beyond M.alpha.
        % Otherwise the cubic step is defined to be either alphamin or alphamax.
        % The quadratic (secant) step is also computed and if the minimum is
        % bracketed then the the step closest to LO.alpha is taken,
        % else the step farthest away is taken.
        %
        info  = 3;
        bound = true;

        if self.isMonotonic( LO, M )
          alphac = LO.alpha + self.xtrapf * (M.alpha - LO.alpha);
          if M.alpha > LO.alpha
            alphac = min( alphac, step_maxmax );
          else
            alphac = max( alphac, self.alpha_min);
          end
        else
          alphac = self.minCubic( LO, M );
        end

        alphas = self.minQuadratic2( M, LO );
        if bracketed
          if abs(M.alpha-alphac) < abs(M.alpha-alphas)
            alphaf = alphac;
          else
            alphaf = alphas;
          end
        else
          if abs(M.alpha-alphac) > abs(M.alpha-alphas)
            alphaf = alphac;
          else
            alphaf = alphas;
          end
        end

      else
        %
        % Fourth case.
        % A lower function value, derivatives of the same sign, and the
        % magnitude of the derivative does not decrease.
        % If the minimum is not bracketed, the step is either alphamin or
        % alphamax, else the cubic step is taken.
        %
        info  = 4;
        bound = false;
        if bracketed
          alphac = self.minCubic( M, HI );
          alphaf = alphac;
        elseif M.alpha > LO.alpha
          alphaf = step_maxmax;
        else
          alphaf = self.step_min;
        end
      end
      %
      % Update the interval of uncertainty.
      % This update does not depend on the new step or the case analysis above.
      %
      if M.f > LO.f
        HI = M;
      else
        if sgnd < 0
          HI = LO;
        end
        LO = M;
      end
      %
      % Compute the new step and safeguard it.
      %
      alphaf = min( alphaf, step_maxmax );
      alphaf = max( alphaf, self.alpha_min );
      if bracketed && bound
        atmp = LO.alpha+0.66*(HI.alpha-LO.alpha);
        if HI.alpha > LO.alpha
          alphaf = min(atmp,alphaf);
        else
          alphaf = max(atmp,alphaf);
        end
      end
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  end

  methods
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    function self = LinesearchMoreThuente()
      self@LinesearchForwardBackward('MoreThuente');
      self.xtol          = 1e-2;
      self.xtrapf        = 4;
      self.f0_extra_epsi = 100*eps;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    function plotDebug( self )
      self.printInfo();
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    function info = getInfo( self )
      info = self.info;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    function printInfo( self )
      switch (self.info)
      case 0
        fprintf('Improper input parameters.\n');
      case 1
        fprintf('The sufficient decrease condition and the directional derivative condition hold.\n');
      case 2
        fprintf('Relative width of the interval of uncertainty is at most xtol.\n');
      case 3
        fprintf('Number of calls to fcn has reached max_fun_eval.\n');
      case 4
        fprintf('The step is at the lower bound alpha_min.\n');
      case 5
        fprintf('The step is at the upper bound alpha_max.\n');
      case 6
        fprintf('Rounding errors prevent further progress.\n');
        fprintf('There may not be a step which satisfies the\n');
        fprintf('sufficient decrease and curvature conditions.\n');
        fprintf('Tolerances may be too small..\n');
      end
    end
    %
    % ----------------------------------------------------------------------
    % Line Search Routine
    % ----------------------------------------------------------------------
    %
    function [ stp, info ] = search( self, stp )
      % The purpose of search is to find a step which satisfies
      % a sufficient decrease condition and a curvature condition.
      %
      % At each stage the subroutine updates an interval of uncertainty with
      % endpoints LO.alpha and HI.alpha. The interval of uncertainty is initially chosen
      % so that it contains a minimizer of the modified function
      %
      %     f(stp) - f(0) - c1*stp*f'(0).
      %
      % If a step is obtained for which the modified function has a nonpositive
      % function value and nonnegative derivative, then the interval of
      % uncertainty is chosen so that it contains a minimizer of f(stp).
      %
      % The algorithm is designed to find a step which satisfies the sufficient
      % decrease condition
      %
      %     f(stp) <= f(0) + c1*stp*f'(0),
      %
      % and the curvature condition
      %
      %     abs(f'(stp)) <=  c2*abs(f'(0)).
      %
      % If c1 is less than c2 and if, for example, the function
      % is bounded below, then there is always a step which satisfies both
      % conditions. If no step can be found which satisfies both conditions,
      % then the algorithm usually stops when rounding errors prevent further
      % progress.
      % In this case stp only satisfies the sufficient decrease condition.
      %
      %	stp is a nonnegative variable.
      %     On input stp contains an initial estimate of a satisfactory step.
      %     On output stp contains the final estimate.
      %
      % c1 and c2 are nonnegative input variables.
      %      Termination occurs when the sufficient decrease condition and the
      %      directional derivative condition are satisfied.
      %
      %	xtol is a nonnegative input variable.
      %      Termination occurs  when the relative width of the interval
      %      of uncertainty is at most xtol.
      %
      %	self.step_min and self.step_max are nonnegative input variables which
      %	  specify lower and upper bounds for the step.
      %
      %	maxfev is a positive integer input variable.
      %        Termination occurs when the number of calls to fcn is at least
      %        maxfev by the end of an iteration.
      %
      %	info is an integer output variable set as follows:
      %
      %	  info = 0  Improper input parameters.
      %
      %	  info = 1  The sufficient decrease condition and the
      %             directional derivative condition hold.
      %
      %	  info = 2  Relative width of the interval of uncertainty
      %		        is at most xtol.
      %
      %	  info = 3  Number of calls to fcn has reached maxfev.
      %
      %	  info = 4  The step is at the lower bound self.step_min.
      %
      %	  info = 5  The step is at the upper bound self.step_max.
      %
      %	  info = 6  Rounding errors prevent further progress.
      %             There may not be a step which satisfies the
      %             sufficient decrease and curvature conditions.
      %             Tolerances may be too small.
      %
      self.info = 0;
      info      = 0;
      %
      % Check the input parameters for errors.
      %
      if stp <= 0
        return;
      end

      [ self.f0, self.Df0 ] = self.fDf(0);
      self.c1Df0 = self.c1*self.Df0;

      self.n_fun_eval = 0;
      self.xtrapf     = 4;
      infoc           = 1;
      step_maxmax     = self.alpha_max;
      %
      % Compute the initial gradient in the search direction
      % and check that s is a descent direction.
      %
      if self.Df0 >= 0
        return;
      end
      %
      % Initialize local variables.
      %
      bracketed = false;
      stage1    = true;
      width     = self.alpha_max - self.alpha_min;
      width1    = width/0.5;
      %
      % The variables LO.alpha, LO.f, LO.Df contain the values of the step,
      % function, and directional derivative at the best step.
      % The variables HI.alpha, HI.f, HI.Df contain the value of the step,
      % function, and derivative at the other endpoint of
      % the interval of uncertainty.
      % The variables stp, f, Df contain the values of the step,
      % function, and derivative at the current step.
      %
      LO.alpha = 0;
      LO.f     = self.f0;
      LO.Df    = self.Df0;
      HI       = LO;

      %
      % Start of iteration.
      %
      while true
        %
        % Set the minimum and maximum steps to correspond
        % to the present interval of uncertainty.
        %
        if bracketed
          self.step_min = min( LO.alpha, HI.alpha );
          self.step_max = max( LO.alpha, HI.alpha );
        else
          self.step_min = LO.alpha;
          self.step_max = stp + self.xtrapf*(stp - LO.alpha);
        end
        %
        % Force the step to be within the bounds self.alpha_min and self.alpha_max.
        %
        stp = min( stp, step_maxmax );
        stp = max( stp, self.alpha_min );
        %
        % If an unusual termination is to occur then let
        % stp be the lowest point obtained so far.
        %
        if (bracketed && (stp <= self.step_min || stp >= self.step_max)) || ...
            infoc == 0 || self.n_fun_eval >= self.max_fun_eval || ...
           (bracketed && self.step_max-self.step_min <= self.xtol*self.step_max)
          stp = LO.alpha;
        end
        %
        % Evaluate the function and gradient at stp
        % and compute the directional derivative.
        %
        [ f, Df ] = self.fDf( stp );

        if ~isfinite(f)
          bracketed = false;
          % in case f(alpha) is infinite try to detect the barrier
          if LO.alpha < HI.alpha
            L = LO;
          else
            L = HI;
          end
          R.alpha = stp;
          R.f     = f;
          R.Df    = Df;
          %
          % check if f(alpha) is infinite
          [ L, R ] = self.infGrow( L, R, stp );

          stp = R.alpha;
          [ f, Df ] = self.fDf( stp );
        end

        % added self.f0_extra_epsi to make more robust the check
        ftest1 = self.f0 + stp*self.c1Df0 + self.f0_extra_epsi;
        %
        % Test for convergence.
        %
        if (bracketed && (stp <= self.step_min || stp >= self.step_max) ) || infoc == 0
          %	Rounding errors prevent further progress.
          % There may not be a step which satisfies the sufficient decrease
          % and curvature conditions. Tolerances may be too small.
          self.info = 6;
        elseif stp == step_maxmax && f <= ftest1 && Df <= self.c1Df0
          %	The step is at the upper bound self.step_max.
          self.info = 5;
        elseif stp == self.alpha_min && (f > ftest1 || Df >= self.c1Df0)
          % The step is at the lower bound self.step_min.
          self.info = 4;
        elseif self.n_fun_eval >= self.max_fun_eval
          % Number of calls to fcn has reached maxfev.
          self.info = 3;
        elseif bracketed && self.step_max-self.step_min <= self.xtol*self.step_max
          % Relative width of the interval of uncertainty is at most xtol.
          self.info = 2;
        elseif f <= ftest1 && abs(Df) <= self.c2*(-self.Df0)
          % The sufficient decrease condition and the directional
          % derivative condition hold.
          self.info = 1;
        end
        %
        % Check for termination.
        %
        if self.info ~= 0
          break;
        end
        %
        % In the first stage we seek a step for which the modified
        % function has a nonpositive value and nonnegative derivative.
        %
        if stage1
          if f <= ftest1 && Df >= min(self.c1,self.c2)*self.Df0
            stage1 = false;
          end
        end
        %
        % A modified function is used to predict the step only if we have not
        % obtained a step for which the modified function has a nonpositive
        % function value and nonnegative derivative, and if a lower function
        % value has been obtained but the decrease is not sufficient.
        %
        if stage1 && f <= LO.f && f > ftest1
          %
          % Define the modified function and derivative values.
          %
          M.alpha = stp;
          M.f     = f - stp*self.c1Df0;
          M.Df    = Df - self.c1Df0;

          LO.f  = LO.f - LO.alpha*self.c1Df0;
          LO.Df = LO.Df - self.c1Df0;

          HI.f  = HI.f - HI.alpha*self.c1Df0;
          HI.Df = HI.Df - self.c1Df0;
          %
          % Call cstep to update the interval of uncertainty
          % and to compute the new step.
          %
          [LO, HI, stp, bracketed, infoc] = self.safeguardedStep( LO, HI, M, bracketed, step_maxmax );
          %
          % Reset the function and gradient values for f.
          %
          LO.f  = LO.f + LO.alpha*self.c1Df0;
          LO.Df = LO.Df + self.c1Df0;

          HI.f  = HI.f + HI.alpha*self.c1Df0;
          HI.Df = HI.Df + self.c1Df0;
        else
          %
          % Call cstep to update the interval of uncertainty
          % and to compute the new step.
          %
          M.alpha = stp;
          M.f     = f;
          M.Df    = Df;
          [LO, HI, stp, bracketed, infoc] = self.safeguardedStep( LO, HI, M, bracketed, step_maxmax );
        end
        %
        % Force a sufficient decrease in the size of the interval of uncertainty.
        %
        if bracketed
          if abs(HI.alpha-LO.alpha) >= 0.66*width1
            stp = LO.alpha + 0.5*(HI.alpha - LO.alpha);
          end
          width1 = width;
          width  = abs(HI.alpha-LO.alpha);
        end
        %
        % End of iteration.
        %
      end
      info = self.info;
    end
    %- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  end
end
