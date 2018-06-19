classdef MinimizationLM < MinimizationND
 %
  % Description
  % -----------
  % Minimization of a nonlinear multiuvariate functions using Levenberg-Marquardt method.
  % The algorithm is describbed in the references.
  % Algorithm is in ref[1]: algorithm 3.16;
  %
  % References
  % ----------
  %
  % ref [1]
  % @article{madsen1999methods,
  %       title={Methods for non-linear least squares problems},
  %       author={Madsen, Kaj and Nielsen, Hans Bruun and Tingleff, Ole},
  %       year={1999}
  % }
  %
  %
  % Authors: Enrico Bertolazzi & Giammarco Valenti
  %
  properties (SetAccess = private, Hidden = true)
    % direction_short %
    % angle_too_small %

  end 
  
  methods
    function self = MinimizationLM( fun )
      self.tol2        = 1e-6;
      self.tol         = 1e-3 ;
      self.max_iter    = 100 ;
      self.debug_state = false ;
      self.FD_D        = true ;
      self.funND       = fun ;
      self.linesearch  = [] ;
      self.tau         = 10^-6;
    end

    function setTau( self , tau )
      % Change tau of the LM algorithm:
      % Note the higher the tau the higher the confidence to start close to the minimum:
      % see ref[1] pag 27

      self.tau = tau;

      fprintf(1,'set tau to %2.6g\n', self.tau );
    end

    function setGradTol( self , tolerance )
      % Change tolerance of the gradient:

      self.tol = tolerance;

      fprintf(1,'set tolerance to %2.10g\n', self.tol );
    end

    function setEpsilon2( self , tolerance )
      % Change tolerance epsilon 2 (see ref[1]):

      self.tol2 = tolerance;

      fprintf(1,'set epsilon2 to %2.10g\n', self.tol2 );
    end


    
    function [x,converged] = minimize( self , x0 )
      % Launch the minimization algorithm

      % Initial values -> see ref[1] algorithm 3.16
      x        = x0 ;
      g         = self.funND.grad( x ).' ;      
      % alpha     = 1 ; No linesearch in Levenberg Marquardt
      converged = false ;
      tau       = self.tau;
      J         = self.funND.jacobian(x); % initial jacobian
      A         = J.' * J;
      mi        = tau * max(diag(A));
      ni        = 2; 
      eps2      = self.tol2;
      
      % verifica come utilizzare:
      % if self.debug_state
      %   self.x_history = reshape( x, length(x), 1 ) ;
      % end

      for iter = 1:self.max_iter
        % check convercence and assign the boolean converged.        
        nrm_g     = norm(g,inf) ;      % infinite norm (max)
        converged = nrm_g < self.tol ; % Is it converged?

        % DEBUG ONLY ----
        if self.debug_state
          fprintf(1,'iter = %5d ||grad f||_inf = %12.6g ...', iter, nrm_g ) ;
        end
        % ---------------

        % Direction(step) search -----------------
        % Solve( (J'J - uI)h = - grad ) 

        h_lm = -  ( A - mi*I ) \ g  ;

        % ----------------------------------------

        % Condition on the h_lm
        nrm_h_lm      = norm(h_lm);
        eps2_x_eps2   = eps2*( norm(x) + eps2 ) ); 

        if ( nrm_h_lm <= eps2_x_eps2 ) 

          self.converged = true; % update the boolean converged

          % DEBUG ONLY ----
          if self.debug_state && self.converged

              fprintf(1,'solution found, || n_lm || = %g < %g\n', nrm_h_lm , eps2_x_eps2 );
  
          end
          % ---------------

          break; % out of the loop ( else then is not needed )

        end

        % Update x
        x_new = x + h_lm;

        % compute L0 - L(h_lm)
        L0_Lh = (1/2) * h_lm.' * ( mi * h_lm - g ); % eq(3.7b) version at page 25 of ref [1]

        % Gain ratio (rho)
        rho   = ( self.funND.eval(x) - self.funND.eval(x_new) ) / ( L0_Lh );

        if rho > 0

          x = x_new; % x update

          J = self.funND.jacobian(x); 

          A = J.'*J; 

          g = self.funND.grad(x);

          self.converged = norm(g,inf) <= self.tol;

          if self.converged            % Converged: stop the algorithm

            % DEBUG ONLY ----
            if self.debug_state && self.converged

                fprintf(1,'solution found, ||grad f||_inf = %g < %g\n', nrm_g, self.tol );

            end
            % ---------------

            break;                % Out of the loop 

          end  

          mi = mi * max( 1/3 , 1 - ( 2*rho - 1 )^3 );

          ni = 2;

        else

          mi = mi*ni;
          
          ni = 2*ni;

        end
      
      end

    end

  end

end


% TO DO
%
% - check the steps
% - check variables
% - check initial values
% - check gradient/jacobian issues
% - check algorithm (save redundant computations)
% - initialize parameters
% - add nick
%
%

