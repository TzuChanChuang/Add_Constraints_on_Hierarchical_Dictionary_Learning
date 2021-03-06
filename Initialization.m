function [Dict,Drls] = Initialization(TrainDat_cat,TrainLabel_cat, TrainDat_dog, TrainLabel_dog, opts)
%----------------------------------------------------------------------
%
%Input : (1) TrainDat*2: 		the training data matrix. 
%                      			Each column is a training sample
%        (2) TrainLabel*2: 		the training data labels
%        (3) opts      : 		the struture of parameters
%               .nClass*2   	the number of classes
%				.num_of_animals the number of animals in training data
%               .lambda   		the parameter of l1-norm energy of coefficient
%               .eta  	  		the parameter of l2-norm of coefficient term
%               .eta_2  	  	the parameter of l2-norm of upper classes' coefficient term
%               .nIter    		the number of iteration
%
%Output: (1) Dict:  the learnt dictionary 
%        (2) Drls:  the labels of learnt dictionary's columns
%        (3) CoefM: Mean Coefficient Matrix. Each column is a mean coef
%                   vector
%        (4) CMlabel: the labels of CoefM's columns.
%
%-----------------------------------------------------------------------
%%%%%%%%%%%%%%%%%%
% normalize energy
%%%%%%%%%%%%%%%%%%
TrainDat(:,:,1) = TrainDat_cat*diag(1./sqrt(sum(TrainDat_cat.*TrainDat_cat)));
TrainDat(:,:,2) = TrainDat_dog*diag(1./sqrt(sum(TrainDat_dog.*TrainDat_dog)));
TrainLabel(:,:,1) = TrainLabel_cat;
TrainLabel(:,:,2) = TrainLabel_dog;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%initialize dict and coefficient
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for h = 1:opts.num_of_animals
	fprintf(['initializing dict & coef, h=' num2str(h) '\n']);

	Dict  =  []; 
	Dlabel = [];				

	for ci = 1:opts.nClass(h)
        fprintf(['class=' num2str(ci) '\n']);
	    cdat          			=    TrainDat(:,TrainLabel(:,:,h)==ci,h);
	    [d, coef_ini]			=    K_SVD(cdat, opts.nIter);
	    Dict      				=    [Dict d];
	    Dlabel    				=    [Dlabel repmat(ci,[1 size(d,2)])];
	end

	Dict_ini(:,:,h) = Dict;
	Dlabel_ini(:,:,h) = Dlabel;
end
%%%%%%%%%%%%%%%%%%%%%%%
%initialize shared dict
%%%%%%%%%%%%%%%%%%%%%%%
for h = 1:opts.num_of_animals
	fprintf(['initializing shared dict, h = ' num2str(h) '\n']);
    nClass = opts.nClass(h);
	[sdClass, sd, sdl, hd, hdl, td, tdl] = init_SharedD_2(Dict_ini(:,:,h), Dlabel_ini(:,:,h), nClass);		
	SharedD_nClass(h) = sdClass;		%sdClass(h) are all the same
	SharedDict_ini(:,:,h) = sd;
	SharedDlabel_oriDic_ini(:,:,h) = sdl;
	HeadDict_ini(:,:,h) = hd;
	HeadDictLabel_ini(:,:,h) = hdl;
	TotalDict_ini(:,:,h) = td;
	TotalDictLabel_ini(:,:,h) = tdl;
end

%load(['allDic_ini.mat']);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%use CVX to initialize Ai=[Ai0, Ai^],  ||Xi-[D0, Di^]Ai||2 + lambda*||Ai||1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for h= 1:opts.num_of_animals
	fprintf(['Initalize coefficients, h = ' num2str(h) '\n']);
	coef_cvx = [];
	for ci = 1:opts.nClass(h)
		fprintf(['Initalize coefficients, class:' num2str(ci) '\n']);
		X  =    TrainDat(:,TrainLabel(:,:,h)==ci,h);
		D  =    TotalDict_ini(:,TotalDictLabel_ini(:,:,h) ==ci,h);
		A  =    zeros(size(D,2),size(X,2));
		m  =	size(A,1);
		n  =	size(A,2);
        p  =    size(D,2);
        
		for j=1:n;
			cvx_begin quiet
				variable a(p);
				minimize (norm(X(:,j)-D*a) + opts.lambda*norm(a,1));
			cvx_end
			A(:,j) = a;
		end
        size(A)
        
        %cvx_begin quiet
		%	variable A(p,n);
		%	minimize (norm(X-D*A) + opts.lambda*norm(A,1));
		%cvx_end
        
		coef_cvx = [coef_cvx A];
	end	
	SharedCoef_cvx = coef_cvx(1:SharedD_nClass(h), :);
 	HeadCoef_cvx = coef_cvx(SharedD_nClass(h)+1:m, :);

	coef(:,:,h) = coef_cvx;
	HeadCoef(:,:,h) = HeadCoef_cvx;
	SharedCoef(:,:,h) = SharedCoef_cvx;
end

%load(['coef_ini.mat']);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Main loop 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
DL_par.tau        =     opts.lambda;
DL_par.eta    	  =     opts.eta;
DL_par.eta_2      =     opts.eta_2;
DL_nit            =     1;
SharedDict 		  =     SharedDict_ini;
HeadDict 		  = 	HeadDict_ini;
HeadDictLabel 	  = 	HeadDictLabel_ini;
Dict 			  = 	TotalDict_ini;
DictLabel 		  = 	TotalDictLabel_ini;
DL_ipts.totalX    =     TrainDat;



while DL_nit<=opts.nIter
	fprintf(['Main loop, iteration: ' num2str(DL_nit) '\n']);
	%%%%%the mean of all the shared coef of all upper classes
	upperSC	= [];	
	upperSC_Label = [];
	for h= 1:opts.num_of_animals		
		upperSC = [upperSC SharedCoef(:,:,h)];
		upperSC_Label = [upperSC_Label repmat(h,[1 size(SharedCoef(:,:,h),2)])];
	end
	mean_upperSC = mean(upperSC,2);
	%%%%%
	for h= 1:opts.num_of_animals
%		fprintf(['Updating coefficients, upperclass:' num2str(h) '\n']);
		DL_par.SharedD_nClass = SharedD_nClass(h);
		DL_par.dls        =     DictLabel(:,:,h);
		DL_ipts.D         =     Dict(:,:,h);   
		DL_ipts.trls      =     TrainLabel(:,:,h);
		DL_ipts.SA_up     =		upperSC;
		DL_ipts.SA_up_l   =		upperSC_Label;
		DL_par.index_h    =     h;
		%DL_par.m_up 	  =     size(SharedDict,2)* size(SharedDict,3); %(2 = number of upper classes);

		if size(DL_ipts.D,1)>size(DL_ipts.D,2)
			DL_par.c        =    1.05*eigs(DL_ipts.D'*DL_ipts.D,1);
	    else
	      	DL_par.c        =    1.05*eigs(DL_ipts.D*DL_ipts.D',1);
	    end
	    %-------------------------
	    %updating the coefficient
	    %-------------------------
	    old_coef = coef(:,:,h);
	    for ci = 1:opts.nClass(h)
%	        fprintf(['Updating coefficients, upperclass:' num2str(h) ', class: ' num2str(ci) '\n']);
	        DL_ipts.X         			=  TrainDat(:,TrainLabel(:,:,h)==ci,h);
	        DL_ipts.A         			=  coef(:,:,h);
	        DL_ipts.SA         			=  SharedCoef(:,:,h);
	        DL_ipts.MUSA 				=  mean_upperSC;
	        DL_ipts.HA 					=  HeadCoef(:,:,h);
	        DL_par.index      			=  ci;
	        [Copts]             		=  UpdateCoef(DL_ipts,DL_par);
	        
	        coef(:,TrainLabel(:,:,h)==ci,h)    	  =  Copts.A;
	        SharedCoef(:,TrainLabel(:,:,h)==ci,h) =  Copts.A(1:SharedD_nClass(h), :);
	        HeadCoef(:,TrainLabel(:,:,h)==ci,h)   =  Copts.A(SharedD_nClass(h)+1:end, :);
	        CMlabel(1,ci,h)        		=  ci;
	        CoefM(:,ci,h)         		=  mean(Copts.A,2);
	    end
	    %MUSA after updating coef
	    upperSC	= [];
	    for h2= 1:opts.num_of_animals		
			upperSC = [upperSC SharedCoef(:,:,h2)];
			upperSC_Label = [upperSC_Label repmat(h2,[1 size(SharedCoef(:,:,h2),2)])];
		end
		mean_upperSC = mean(upperSC,2);
		DL_ipts.MUSA =  mean_upperSC;
		DL_ipts.SA_up     =		upperSC;
		DL_ipts.SA_up_l   =		upperSC_Label;
	    
		fprintf(['check if coef updated: iteration=' num2str(DL_nit) '; h=' num2str(h) '\n']);
	    check = isequal(coef(:,:,h), old_coef);
	    if(check)
	    	fprintf(['the same!!QQ']);
	   	else
	   		fprintf(['updated!!yay']);
	   	end

	    [GAP_coding(h, DL_nit)]  =  Total_Energy(TrainDat(:,:,h),coef(:,:,h),SharedCoef(:,:,h),HeadCoef(:,:,h),opts.nClass(h),DL_par,DL_ipts);	 
	    %------------------------------------------------------------
	    %updating the dictionary Di^ : min||Xi - D0*Ai0 - Di^*Ai^||2
	    %------------------------------------------------------------
	    old_headdic = HeadDict(:,:,h);
	    for ci = 1:opts.nClass(h)
%	    	fprintf(['Updating Di^, upperclass' num2str(h) 'class: ' num2str(ci) '\n']);
	 		Xi = TrainDat(:, TrainLabel(:,:,h)==ci, h) - SharedDict(:,:,h) * SharedCoef(:, TrainLabel(:,:,h)==ci, h);
	    	c = 1;
	    	Dinit_ci = HeadDict(:, HeadDictLabel(:,:,h)==ci, h);
	    	Ai = HeadCoef(:, TrainLabel(:,:,h)==ci, h);
	    	HeadDict(:, HeadDictLabel(:,:,h)==ci, h)   =  learn_basis_dual(TrainDat(:,TrainLabel(:,:,h)==ci, h), Ai, c, Dinit_ci);
	    end
	    fprintf(['check if head_dic updated: iteration=' num2str(DL_nit) '; h=' num2str(h) '\n']);
	    check = isequal(HeadDict(:,:,h), old_headdic);
	    if(check)
	    	fprintf(['the same!!QQ\n']);
	   	else
	   		fprintf(['updated!!yay\n']);
	   	end
	    %------------------------------------------------------------
	    %updating the dictionary D0 : min||X0 - D0*Ai0||2
	    %------------------------------------------------------------
	    old_shareddic = SharedDict(:,:,h);
%	    fprintf(['Updating D0 , upperclass' num2str(h) '\n']);
	    A0 = SharedCoef(:,:,h);
	    Dinit_shared = SharedDict(:,:,h);
	    c = 1;
	    X0 = [];
	    for ci = 1:opts.nClass(h)
	    	Xi = TrainDat(:, TrainLabel(:,:,h)==ci, h) - HeadDict(:, HeadDictLabel(:,:,h)==ci, h) * HeadCoef(:, TrainLabel(:,:,h)==ci, h);
	    	X0 = [X0 Xi];
	    end
		SharedDict(:,:,h)   = learn_basis_dual(X0, A0, c, Dinit_shared);

		fprintf(['check if shared_dic updated: iteration=' num2str(DL_nit) '; h=' num2str(h) '\n']);
	    check = isequal(SharedDict(:,:,h), old_shareddic);
	    if(check)
	    	fprintf(['the same!!QQ\n']);
	   	else
	   		fprintf(['updated!!yay\n']);
	   	end

		%combine Dict
		for ci = 1:opts.nClass(h)
			Dict(:,DictLabel(:,:,h)==ci,h) = [SharedDict(:,:,h) HeadDict(:,HeadDictLabel(:,:,h)==ci,h)];
		end
		DL_ipts.D 	= 	Dict(:,:,h);
		[GAP_Dict(h, DL_nit)]  =  Total_Energy(TrainDat(:,:,h),coef(:,:,h),SharedCoef(:,:,h),HeadCoef(:,:,h),opts.nClass(h),DL_par,DL_ipts);	
	end

	DL_nit = DL_nit+1;
end
Drls = DictLabel;

figure;
subplot(1,2,1);plot(1:size(GAP_coding,2), GAP_coding(1, :),'-*', 1:size(GAP_coding,2), GAP_coding(2, :), '-o');title('GAP_coding');
subplot(1,2,2);plot(1:size(GAP_Dict,2), GAP_Dict(1, :),'-*', 1:size(GAP_Dict,2), GAP_Dict(2, :), '-o');title('GAP_Dict');

figure;
plot(1:size(GAP_Dict,2), GAP_Dict(2, :), '-o');title('GAP');



return;

