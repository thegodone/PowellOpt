 
module cobyla_module
 
    use kind_module, only: wp
	
    implicit real (wp) (a-h, o-z)
 
    private
 
    abstract interface
    subroutine func (n, m, x, f, con)!! calcfc interface
        import :: wp
        implicit none
        integer :: n
        integer :: m
        real (wp) :: x (*)
        real (wp) :: f
        real (wp) :: con (*)
    end subroutine func
    end interface
 
    public :: cobyla
    public :: cobyla_test
 
contains
 
    subroutine cobyla (n, m, x, rhobeg, rhoend, iprint, maxfun, w, iact, calcfc)
        dimension x (*), w (*), iact (*)
        procedure (func) :: calcfc
!
!     This subroutine minimizes an objective function F(X) subject to M
!     inequality constraints on X, where X is a vector of variables that has
!     N components. The algorithm employs linear approximations to the
!     objective and constraint functions, the approximations being formed by
!     linear interpolation at N+1 points in the space of the variables.
!     We regard these interpolation points as vertices of a simplex. The
!     parameter RHO controls the size of the simplex and it is reduced
!     automatically from RHOBEG to RHOEND. For each RHO the subroutine tries
!     to achieve a good vector of variables for the current size, and then
!     RHO is reduced until the value RHOEND is reached. Therefore RHOBEG and
!     RHOEND should be set to reasonable initial changes to and the required
!     accuracy in the variables respectively, but this accuracy should be
!     viewed as a subject for experimentation because it is not guaranteed.
!     The subroutine has an advantage over many of its competitors, however,
!     which is that it treats each constraint individually when calculating
!     a change to the variables, instead of lumping the constraints together
!     into a single penalty function. The name of the subroutine is derived
!     from the phrase Constrained Optimization BY Linear Approximations.
!
!     The user must set the values of N, M, RHOBEG and RHOEND, and must
!     provide an initial vector of variables in X. Further, the value of
!     IPRINT should be set to 0, 1, 2 or 3, which controls the amount of
!     printing during the calculation. Specifically, there is no output if
!     IPRINT=0 and there is output only at the end of the calculation if
!     IPRINT=1. Otherwise each new value of RHO and SIGMA is printed.
!     Further, the vector of variables and some function information are
!     given either when RHO is reduced or when each new value of F(X) is
!     computed in the cases IPRINT=2 or IPRINT=3 respectively. Here SIGMA
!     is a penalty parameter, it being assumed that a change to X is an
!     improvement if it reduces the merit function
!                F(X)+SIGMA*MAX(0.0,-C1(X),-C2(X),...,-CM(X)),
!     where C1,C2,...,CM denote the constraint functions that should become
!     nonnegative eventually, at least to the precision of RHOEND. In the
!     printed output the displayed term that is multiplied by SIGMA is
!     called MAXCV, which stands for 'MAXimum Constraint Violation'. The
!     argument MAXFUN is an integer variable that must be set by the user to a
!     limit on the number of calls of CALCFC, the purpose of this routine being
!     given below. The value of MAXFUN will be altered to the number of calls
!     of CALCFC that are made. The arguments W and IACT provide real and
!     integer arrays that are used as working space. Their lengths must be at
!     least N*(3*N+2*M+11)+4*M+6 and M+1 respectively.
!
!     In order to define the objective and constraint functions, we require
!     a subroutine that has the name and arguments
!                SUBROUTINE CALCFC (N,M,X,F,CON)
!                DIMENSION X(*),CON(*)  .
!     The values of N and M are fixed and have been defined already, while
!     X is now the current vector of variables. The subroutine should return
!     the objective and constraint functions at X in F and CON(1),CON(2),
!     ...,CON(M). Note that we are trying to adjust X so that F(X) is as
!     small as possible subject to the constraint functions being nonnegative.
!
!     Partition the working space array W to provide the storage that is needed
!     for the main calculation.
!
        mpp = m + 2
        icon = 1
        isim = icon + mpp
        isimi = isim + n * n + n
        idatm = isimi + n * n
        ia = idatm + n * mpp + mpp
        ivsig = ia + m * n + n
        iveta = ivsig + n
        isigb = iveta + n
        idx = isigb + n
        iwork = idx + n
 
        call cobylb (n, m, mpp, x, rhobeg, rhoend, iprint, maxfun, w(icon), w(isim), &
       & w(isimi), w(idatm), w(ia), w(ivsig), w(iveta), w(isigb), w(idx), w(iwork), iact, &
       & calcfc)
 
    end subroutine cobyla
 
    subroutine cobylb (n, m, mpp, x, rhobeg, rhoend, iprint, maxfun, con, sim, simi, &
   & datmat, a, vsig, veta, sigbar, dx, w, iact, calcfc)
        dimension x (*), con (*), sim (n,*), simi (n,*), datmat (mpp,*), a (n,*), vsig &
       & (*), veta (*), sigbar (*), dx (*), w (*), iact (*)
        procedure (func) :: calcfc
!
!     Set the initial values of some parameters. The last column of SIM holds
!     the optimal vertex of the current simplex, and the preceding N columns
!     hold the displacements from the optimal vertex to the other vertices.
!     Further, SIMI holds the inverse of the matrix that is contained in the
!     first N columns of SIM.
!
        iptem = min (n, 5)
        iptemp = iptem + 1
        np = n + 1
        mp = m + 1
        alpha = 0.25_wp
        beta = 2.1_wp
        gamma = 0.5_wp
        delta = 1.1_wp
        rho = rhobeg
        parmu = 0.0_wp
        if (iprint >= 2) print 10, rho
10      format (/ 3 x, 'The initial value of RHO is', 1 pe13.6, 2 x,&
        'and PARMU is set to zero.')
        nfvals = 0
        temp = 1.0_wp / rho
        do 30 i = 1, n
            sim (i, np) = x (i)
            do 20 j = 1, n
                sim (i, j) = 0.0_wp
20          simi (i, j) = 0.0_wp
            sim (i, i) = rho
30      simi (i, i) = temp
        jdrop = np
        ibrnch = 0
!
!     Make the next call of the user-supplied subroutine CALCFC. These
!     instructions are also used for calling CALCFC during the iterations of
!     the algorithm.
!
40      if (nfvals >= maxfun .and. nfvals > 0) then
            if (iprint >= 1) print 50
50          format (/ 3 x, 'Return from subroutine COBYLA because the ',&
            'MAXFUN limit has been reached.')
            go to 600
        end if
        nfvals = nfvals + 1
        call calcfc (n, m, x, f, con)
        resmax = 0.0_wp
        if (m > 0) then
            do 60 k = 1, m
60          resmax = max (resmax,-con(k))
        end if
        if (nfvals == iprint-1 .or. iprint == 3) then
            print 70, nfvals, f, resmax, (x(i), i=1, iptem)
70          format (/ 3 x, 'NFVALS =', i5, 3 x, 'F =', 1 pe13.6, 4 x, 'MAXCV =', 1 pe13.6 &
           & / 3 x, 'X =', 1 pe13.6, 1 p4e15.6)
            if (iptem < n) print 80, (x(i), i=iptemp, n)
80          format (1 pe19.6, 1 p4e15.6)
        end if
        con (mp) = f
        con (mpp) = resmax
        if (ibrnch == 1) go to 440
!
!     Set the recently calculated function values in a column of DATMAT. This
!     array has a column for each vertex of the current simplex, the entries of
!     each column being the values of the constraint functions (if any)
!     followed by the objective function and the greatest constraint violation
!     at the vertex.
!
        do 90 k = 1, mpp
90      datmat (k, jdrop) = con (k)
        if (nfvals > np) go to 130
!
!     Exchange the new vertex of the initial simplex with the optimal vertex if
!     necessary. Then, if the initial simplex is not complete, pick its next
!     vertex and calculate the function values there.
!
        if (jdrop <= n) then
            if (datmat(mp, np) <= f) then
                x (jdrop) = sim (jdrop, np)
            else
                sim (jdrop, np) = x (jdrop)
                do 100 k = 1, mpp
                    datmat (k, jdrop) = datmat (k, np)
100             datmat (k, np) = con (k)
                do 120 k = 1, jdrop
                    sim (jdrop, k) = - rho
                    temp = 0.0_wp
                    do 110 i = k, jdrop
110                 temp = temp - simi (i, k)
120             simi (jdrop, k) = temp
            end if
        end if
        if (nfvals <= n) then
            jdrop = nfvals
            x (jdrop) = x (jdrop) + rho
            go to 40
        end if
130     ibrnch = 1
!
!     Identify the optimal vertex of the current simplex.
!
140     phimin = datmat (mp, np) + parmu * datmat (mpp, np)
        nbest = np
        do 150 j = 1, n
            temp = datmat (mp, j) + parmu * datmat (mpp, j)
            if (temp < phimin) then
                nbest = j
                phimin = temp
            else if (temp == phimin .and. parmu == 0.0_wp) then
                if (datmat(mpp, j) < datmat(mpp, nbest)) nbest = j
            end if
150     continue
!
!     Switch the best vertex into pole position if it is not there already,
!     and also update SIM, SIMI and DATMAT.
!
        if (nbest <= n) then
            do 160 i = 1, mpp
                temp = datmat (i, np)
                datmat (i, np) = datmat (i, nbest)
160         datmat (i, nbest) = temp
            do 180 i = 1, n
                temp = sim (i, nbest)
                sim (i, nbest) = 0.0_wp
                sim (i, np) = sim (i, np) + temp
                tempa = 0.0_wp
                do 170 k = 1, n
                    sim (i, k) = sim (i, k) - temp
170             tempa = tempa - simi (k, i)
180         simi (nbest, i) = tempa
        end if
!
!     Make an error return if SIGI is a poor approximation to the inverse of
!     the leading N by N submatrix of SIG.
!
        error = 0.0_wp
        do 200 i = 1, n
            do 200 j = 1, n
                temp = 0.0_wp
                if (i == j) temp = temp - 1.0_wp
                do 190 k = 1, n
190             temp = temp + simi (i, k) * sim (k, j)
200     error = max (error, abs(temp))
        if (error > 0.1_wp) then
            if (iprint >= 1) print 210
210         format (/ 3 x, 'Return from subroutine COBYLA because ',&
            'rounding errors are becoming damaging.')
            go to 600
        end if
!
!     Calculate the coefficients of the linear approximations to the objective
!     and constraint functions, placing minus the objective function gradient
!     after the constraint gradients in the array A. The vector W is used for
!     working space.
!
        do 240 k = 1, mp
            con (k) = - datmat (k, np)
            do 220 j = 1, n
220         w (j) = datmat (k, j) + con (k)
            do 240 i = 1, n
                temp = 0.0_wp
                do 230 j = 1, n
230             temp = temp + w (j) * simi (j, i)
                if (k == mp) temp = - temp
240     a (i, k) = temp
!
!     Calculate the values of sigma and eta, and set IFLAG=0 if the current
!     simplex is not acceptable.
!
        iflag = 1
        parsig = alpha * rho
        pareta = beta * rho
        do 260 j = 1, n
            wsig = 0.0_wp
            weta = 0.0_wp
            do 250 i = 1, n
                wsig = wsig + simi (j, i) ** 2
250         weta = weta + sim (i, j) ** 2
            vsig (j) = 1.0_wp / sqrt (wsig)
            veta (j) = sqrt (weta)
            if (vsig(j) < parsig .or. veta(j) > pareta) iflag = 0
260     continue
!
!     If a new vertex is needed to improve acceptability, then decide which
!     vertex to drop from the simplex.
!
        if (ibrnch == 1 .or. iflag == 1) go to 370
        jdrop = 0
        temp = pareta
        do 270 j = 1, n
            if (veta(j) > temp) then
                jdrop = j
                temp = veta (j)
            end if
270     continue
        if (jdrop == 0) then
            do 280 j = 1, n
                if (vsig(j) < temp) then
                    jdrop = j
                    temp = vsig (j)
                end if
280         continue
        end if
!
!     Calculate the step to the new vertex and its sign.
!
        temp = gamma * rho * vsig (jdrop)
        do 290 i = 1, n
290     dx (i) = temp * simi (jdrop, i)
        cvmaxp = 0.0_wp
        cvmaxm = 0.0_wp
        do 310 k = 1, mp
            sum = 0.0_wp
            do 300 i = 1, n
300         sum = sum + a (i, k) * dx (i)
            if (k < mp) then
                temp = datmat (k, np)
                cvmaxp = max (cvmaxp,-sum-temp)
                cvmaxm = max (cvmaxm, sum-temp)
            end if
310     continue
        dxsign = 1.0_wp
        if (parmu*(cvmaxp-cvmaxm) > sum+sum) dxsign = - 1.0_wp
!
!     Update the elements of SIM and SIMI, and set the next X.
!
        temp = 0.0_wp
        do 320 i = 1, n
            dx (i) = dxsign * dx (i)
            sim (i, jdrop) = dx (i)
320     temp = temp + simi (jdrop, i) * dx (i)
        do 330 i = 1, n
330     simi (jdrop, i) = simi (jdrop, i) / temp
        do 360 j = 1, n
            if (j /= jdrop) then
                temp = 0.0_wp
                do 340 i = 1, n
340             temp = temp + simi (j, i) * dx (i)
                do 350 i = 1, n
350             simi (j, i) = simi (j, i) - temp * simi (jdrop, i)
            end if
360     x (j) = sim (j, np) + dx (j)
        go to 40
!
!     Calculate DX=x(*)-x(0). Branch if the length of DX is less than 0.5*RHO.
!
370     iz = 1
        izdota = iz + n * n
        ivmc = izdota + n
        isdirn = ivmc + mp
        idxnew = isdirn + n
        ivmd = idxnew + n
        call trstlp (n, m, a, con, rho, dx, ifull, iact, w(iz), w(izdota), w(ivmc), &
       & w(isdirn), w(idxnew), w(ivmd))
        if (ifull == 0) then
            temp = 0.0_wp
            do 380 i = 1, n
380         temp = temp + dx (i) ** 2
            if (temp < 0.25_wp*rho*rho) then
                ibrnch = 1
                go to 550
            end if
        end if
!
!     Predict the change to F and the new maximum constraint violation if the
!     variables are altered from x(0) to x(0)+DX.
!
        resnew = 0.0_wp
        con (mp) = 0.0_wp
        do 400 k = 1, mp
            sum = con (k)
            do 390 i = 1, n
390         sum = sum - a (i, k) * dx (i)
            if (k < mp) resnew = max (resnew, sum)
400     continue
!
!     Increase PARMU if necessary and branch back if this change alters the
!     optimal vertex. Otherwise PREREM and PREREC will be set to the predicted
!     reductions in the merit function and the maximum constraint violation
!     respectively.
!
        barmu = 0.0_wp
        prerec = datmat (mpp, np) - resnew
        if (prerec > 0.0_wp) barmu = sum / prerec
        if (parmu < 1.5_wp*barmu) then
            parmu = 2.0_wp * barmu
            if (iprint >= 2) print 410, parmu
410         format (/ 3 x, 'Increase in PARMU to', 1 pe13.6)
            phi = datmat (mp, np) + parmu * datmat (mpp, np)
            do 420 j = 1, n
                temp = datmat (mp, j) + parmu * datmat (mpp, j)
                if (temp < phi) go to 140
                if (temp == phi .and. parmu == 0.0_wp) then
                    if (datmat(mpp, j) < datmat(mpp, np)) go to 140
                end if
420         continue
        end if
        prerem = parmu * prerec - sum
!
!     Calculate the constraint and objective functions at x(*). Then find the
!     actual reduction in the merit function.
!
        do 430 i = 1, n
430     x (i) = sim (i, np) + dx (i)
        ibrnch = 1
        go to 40
440     vmold = datmat (mp, np) + parmu * datmat (mpp, np)
        vmnew = f + parmu * resmax
        trured = vmold - vmnew
        if (parmu == 0.0_wp .and. f == datmat(mp, np)) then
            prerem = prerec
            trured = datmat (mpp, np) - resmax
        end if
!
!     Begin the operations that decide whether x(*) should replace one of the
!     vertices of the current simplex, the change being mandatory if TRURED is
!     positive. Firstly, JDROP is set to the index of the vertex that is to be
!     replaced.
!
        ratio = 0.0_wp
        if (trured <= 0.0_wp) ratio = 1.0_wp
        jdrop = 0
        do 460 j = 1, n
            temp = 0.0_wp
            do 450 i = 1, n
450         temp = temp + simi (j, i) * dx (i)
            temp = abs (temp)
            if (temp > ratio) then
                jdrop = j
                ratio = temp
            end if
460     sigbar (j) = temp * vsig (j)
!
!     Calculate the value of ell.
!
        edgmax = delta * rho
        l = 0
        do 480 j = 1, n
            if (sigbar(j) >= parsig .or. sigbar(j) >= vsig(j)) then
                temp = veta (j)
                if (trured > 0.0_wp) then
                    temp = 0.0_wp
                    do 470 i = 1, n
470                 temp = temp + (dx(i)-sim(i, j)) ** 2
                    temp = sqrt (temp)
                end if
                if (temp > edgmax) then
                    l = j
                    edgmax = temp
                end if
            end if
480     continue
        if (l > 0) jdrop = l
        if (jdrop == 0) go to 550
!
!     Revise the simplex by updating the elements of SIM, SIMI and DATMAT.
!
        temp = 0.0_wp
        do 490 i = 1, n
            sim (i, jdrop) = dx (i)
490     temp = temp + simi (jdrop, i) * dx (i)
        do 500 i = 1, n
500     simi (jdrop, i) = simi (jdrop, i) / temp
        do 530 j = 1, n
            if (j /= jdrop) then
                temp = 0.0_wp
                do 510 i = 1, n
510             temp = temp + simi (j, i) * dx (i)
                do 520 i = 1, n
520             simi (j, i) = simi (j, i) - temp * simi (jdrop, i)
            end if
530     continue
        do 540 k = 1, mpp
540     datmat (k, jdrop) = con (k)
!
!     Branch back for further iterations with the current RHO.
!
        if (trured > 0.0_wp .and. trured >= 0.1_wp*prerem) go to 140
550     if (iflag == 0) then
            ibrnch = 0
            go to 140
        end if
!
!     Otherwise reduce RHO if it is not at its least value and reset PARMU.
!
        if (rho > rhoend) then
            rho = 0.5_wp * rho
            if (rho <= 1.5_wp*rhoend) rho = rhoend
            if (parmu > 0.0_wp) then
                denom = 0.0_wp
                do 570 k = 1, mp
                    cmin = datmat (k, np)
                    cmax = cmin
                    do 560 i = 1, n
                        cmin = min (cmin, datmat(k, i))
560                 cmax = max (cmax, datmat(k, i))
                    if (k <= m .and. cmin < 0.5_wp*cmax) then
                        temp = max (cmax, 0.0_wp) - cmin
                        if (denom <= 0.0_wp) then
                            denom = temp
                        else
                            denom = min (denom, temp)
                        end if
                    end if
570             continue
                if (denom == 0.0_wp) then
                    parmu = 0.0_wp
                else if (cmax-cmin < parmu*denom) then
                    parmu = (cmax-cmin) / denom
                end if
            end if
            if (iprint >= 2) print 580, rho, parmu
580         format (/ 3 x, 'Reduction in RHO to', 1 pe13.6, '  and PARMU =', 1 pe13.6)
            if (iprint == 2) then
                print 70, nfvals, datmat (mp, np), datmat (mpp, np), (sim(i, np), i=1, &
               & iptem)
                if (iptem < n) print 80, (x(i), i=iptemp, n)
            end if
            go to 140
        end if
!
!     Return the best calculated values of the variables.
!
        if (iprint >= 1) print 590
590     format (/ 3 x, 'Normal return from subroutine COBYLA')
        if (ifull == 1) go to 620
600     do 610 i = 1, n
610     x (i) = sim (i, np)
        f = datmat (mp, np)
        resmax = datmat (mpp, np)
620     if (iprint >= 1) then
            print 70, nfvals, f, resmax, (x(i), i=1, iptem)
            if (iptem < n) print 80, (x(i), i=iptemp, n)
        end if
        maxfun = nfvals
 
    end subroutine cobylb
 
    subroutine trstlp (n, m, a, b, rho, dx, ifull, iact, z, zdota, vmultc, sdirn, dxnew, &
   & vmultd)
        dimension a (n,*), b (*), dx (*), iact (*), z (n,*), zdota (*), vmultc (*), sdirn &
       & (*), dxnew (*), vmultd (*)
!
!     This subroutine calculates an N-component vector DX by applying the
!     following two stages. In the first stage, DX is set to the shortest
!     vector that minimizes the greatest violation of the constraints
!       A(1,K)*DX(1)+A(2,K)*DX(2)+...+A(N,K)*DX(N) .GE. B(K), K=2,3,...,M,
!     subject to the Euclidean length of DX being at most RHO. If its length is
!     strictly less than RHO, then we use the resultant freedom in DX to
!     minimize the objective function
!              -A(1,M+1)*DX(1)-A(2,M+1)*DX(2)-...-A(N,M+1)*DX(N)
!     subject to no increase in any greatest constraint violation. This
!     notation allows the gradient of the objective function to be regarded as
!     the gradient of a constraint. Therefore the two stages are distinguished
!     by MCON .EQ. M and MCON .GT. M respectively. It is possible that a
!     degeneracy may prevent DX from attaining the target length RHO. Then the
!     value IFULL=0 would be set, but usually IFULL=1 on return.
!
!     In general NACT is the number of constraints in the active set and
!     IACT(1),...,IACT(NACT) are their indices, while the remainder of IACT
!     contains a permutation of the remaining constraint indices. Further, Z is
!     an orthogonal matrix whose first NACT columns can be regarded as the
!     result of Gram-Schmidt applied to the active constraint gradients. For
!     J=1,2,...,NACT, the number ZDOTA(J) is the scalar product of the J-th
!     column of Z with the gradient of the J-th active constraint. DX is the
!     current vector of variables and here the residuals of the active
!     constraints should be zero. Further, the active constraints have
!     nonnegative Lagrange multipliers that are held at the beginning of
!     VMULTC. The remainder of this vector holds the residuals of the inactive
!     constraints at DX, the ordering of the components of VMULTC being in
!     agreement with the permutation of the indices of the constraints that is
!     in IACT. All these residuals are nonnegative, which is achieved by the
!     shift RESMAX that makes the least residual zero.
!
!     Initialize Z and some other variables. The value of RESMAX will be
!     appropriate to DX=0, while ICON will be the index of a most violated
!     constraint if RESMAX is positive. Usually during the first stage the
!     vector SDIRN gives a search direction that reduces all the active
!     constraint violations by one simultaneously.
!
        ifull = 1
        mcon = m
        nact = 0
        resmax = 0.0_wp
        do 20 i = 1, n
            do 10 j = 1, n
10          z (i, j) = 0.0_wp
            z (i, i) = 1.0_wp
20      dx (i) = 0.0_wp
        if (m >= 1) then
            do 30 k = 1, m
                if (b(k) > resmax) then
                    resmax = b (k)
                    icon = k
                end if
30          continue
            do 40 k = 1, m
                iact (k) = k
40          vmultc (k) = resmax - b (k)
        end if
        if (resmax == 0.0_wp) go to 480
        do 50 i = 1, n
50      sdirn (i) = 0.0_wp
!
!     End the current stage of the calculation if 3 consecutive iterations
!     have either failed to reduce the best calculated value of the objective
!     function or to increase the number of active constraints since the best
!     value was calculated. This strategy prevents cycling, but there is a
!     remote possibility that it will cause premature termination.
!
60      optold = 0.0_wp
        icount = 0
70      if (mcon == m) then
            optnew = resmax
        else
            optnew = 0.0_wp
            do 80 i = 1, n
80          optnew = optnew - dx (i) * a (i, mcon)
        end if
        if (icount == 0 .or. optnew < optold) then
            optold = optnew
            nactx = nact
            icount = 3
        else if (nact > nactx) then
            nactx = nact
            icount = 3
        else
            icount = icount - 1
            if (icount == 0) go to 490
        end if
!
!     If ICON exceeds NACT, then we add the constraint with index IACT(ICON) to
!     the active set. Apply Givens rotations so that the last N-NACT-1 columns
!     of Z are orthogonal to the gradient of the new constraint, a scalar
!     product being set to zero if its nonzero value could be due to computer
!     rounding errors. The array DXNEW is used for working space.
!
        if (icon <= nact) go to 260
        kk = iact (icon)
        do 90 i = 1, n
90      dxnew (i) = a (i, kk)
        tot = 0.0_wp
        k = n
100     if (k > nact) then
            sp = 0.0_wp
            spabs = 0.0_wp
            do 110 i = 1, n
                temp = z (i, k) * dxnew (i)
                sp = sp + temp
110         spabs = spabs + abs (temp)
            acca = spabs + 0.1_wp * abs (sp)
            accb = spabs + 0.2_wp * abs (sp)
            if (spabs >= acca .or. acca >= accb) sp = 0.0_wp
            if (tot == 0.0_wp) then
                tot = sp
            else
                kp = k + 1
                temp = sqrt (sp*sp+tot*tot)
                alpha = sp / temp
                beta = tot / temp
                tot = temp
                do 120 i = 1, n
                    temp = alpha * z (i, k) + beta * z (i, kp)
                    z (i, kp) = alpha * z (i, kp) - beta * z (i, k)
120             z (i, k) = temp
            end if
            k = k - 1
            go to 100
        end if
!
!     Add the new constraint if this can be done without a deletion from the
!     active set.
!
        if (tot /= 0.0_wp) then
            nact = nact + 1
            zdota (nact) = tot
            vmultc (icon) = vmultc (nact)
            vmultc (nact) = 0.0_wp
            go to 210
        end if
!
!     The next instruction is reached if a deletion has to be made from the
!     active set in order to make room for the new active constraint, because
!     the new constraint gradient is a linear combination of the gradients of
!     the old active constraints. Set the elements of VMULTD to the multipliers
!     of the linear combination. Further, set IOUT to the index of the
!     constraint to be deleted, but branch if no suitable index can be found.
!
        ratio = - 1.0_wp
        k = nact
130     zdotv = 0.0_wp
        zdvabs = 0.0_wp
        do 140 i = 1, n
            temp = z (i, k) * dxnew (i)
            zdotv = zdotv + temp
140     zdvabs = zdvabs + abs (temp)
        acca = zdvabs + 0.1_wp * abs (zdotv)
        accb = zdvabs + 0.2_wp * abs (zdotv)
        if (zdvabs < acca .and. acca < accb) then
            temp = zdotv / zdota (k)
            if (temp > 0.0_wp .and. iact(k) <= m) then
                tempa = vmultc (k) / temp
                if (ratio < 0.0_wp .or. tempa < ratio) then
                    ratio = tempa
                    iout = k
                end if
            end if
            if (k >= 2) then
                kw = iact (k)
                do 150 i = 1, n
150             dxnew (i) = dxnew (i) - temp * a (i, kw)
            end if
            vmultd (k) = temp
        else
            vmultd (k) = 0.0_wp
        end if
        k = k - 1
        if (k > 0) go to 130
        if (ratio < 0.0_wp) go to 490
!
!     Revise the Lagrange multipliers and reorder the active constraints so
!     that the one to be replaced is at the end of the list. Also calculate the
!     new value of ZDOTA(NACT) and branch if it is not acceptable.
!
        do 160 k = 1, nact
160     vmultc (k) = max (0.0_wp, vmultc(k)-ratio*vmultd(k))
        if (icon < nact) then
            isave = iact (icon)
            vsave = vmultc (icon)
            k = icon
170         kp = k + 1
            kw = iact (kp)
            sp = 0.0_wp
            do 180 i = 1, n
180         sp = sp + z (i, k) * a (i, kw)
            temp = sqrt (sp*sp+zdota(kp)**2)
            alpha = zdota (kp) / temp
            beta = sp / temp
            zdota (kp) = alpha * zdota (k)
            zdota (k) = temp
            do 190 i = 1, n
                temp = alpha * z (i, kp) + beta * z (i, k)
                z (i, kp) = alpha * z (i, k) - beta * z (i, kp)
190         z (i, k) = temp
            iact (k) = kw
            vmultc (k) = vmultc (kp)
            k = kp
            if (k < nact) go to 170
            iact (k) = isave
            vmultc (k) = vsave
        end if
        temp = 0.0_wp
        do 200 i = 1, n
200     temp = temp + z (i, nact) * a (i, kk)
        if (temp == 0.0_wp) go to 490
        zdota (nact) = temp
        vmultc (icon) = 0.0_wp
        vmultc (nact) = ratio
!
!     Update IACT and ensure that the objective function continues to be
!     treated as the last active constraint when MCON>M.
!
210     iact (icon) = iact (nact)
        iact (nact) = kk
        if (mcon > m .and. kk /= mcon) then
            k = nact - 1
            sp = 0.0_wp
            do 220 i = 1, n
220         sp = sp + z (i, k) * a (i, kk)
            temp = sqrt (sp*sp+zdota(nact)**2)
            alpha = zdota (nact) / temp
            beta = sp / temp
            zdota (nact) = alpha * zdota (k)
            zdota (k) = temp
            do 230 i = 1, n
                temp = alpha * z (i, nact) + beta * z (i, k)
                z (i, nact) = alpha * z (i, k) - beta * z (i, nact)
230         z (i, k) = temp
            iact (nact) = iact (k)
            iact (k) = kk
            temp = vmultc (k)
            vmultc (k) = vmultc (nact)
            vmultc (nact) = temp
        end if
!
!     If stage one is in progress, then set SDIRN to the direction of the next
!     change to the current vector of variables.
!
        if (mcon > m) go to 320
        kk = iact (nact)
        temp = 0.0_wp
        do 240 i = 1, n
240     temp = temp + sdirn (i) * a (i, kk)
        temp = temp - 1.0_wp
        temp = temp / zdota (nact)
        do 250 i = 1, n
250     sdirn (i) = sdirn (i) - temp * z (i, nact)
        go to 340
!
!     Delete the constraint that has the index IACT(ICON) from the active set.
!
260     if (icon < nact) then
            isave = iact (icon)
            vsave = vmultc (icon)
            k = icon
270         kp = k + 1
            kk = iact (kp)
            sp = 0.0_wp
            do 280 i = 1, n
280         sp = sp + z (i, k) * a (i, kk)
            temp = sqrt (sp*sp+zdota(kp)**2)
            alpha = zdota (kp) / temp
            beta = sp / temp
            zdota (kp) = alpha * zdota (k)
            zdota (k) = temp
            do 290 i = 1, n
                temp = alpha * z (i, kp) + beta * z (i, k)
                z (i, kp) = alpha * z (i, k) - beta * z (i, kp)
290         z (i, k) = temp
            iact (k) = kk
            vmultc (k) = vmultc (kp)
            k = kp
            if (k < nact) go to 270
            iact (k) = isave
            vmultc (k) = vsave
        end if
        nact = nact - 1
!
!     If stage one is in progress, then set SDIRN to the direction of the next
!     change to the current vector of variables.
!
        if (mcon > m) go to 320
        temp = 0.0_wp
        do 300 i = 1, n
300     temp = temp + sdirn (i) * z (i, nact+1)
        do 310 i = 1, n
310     sdirn (i) = sdirn (i) - temp * z (i, nact+1)
        go to 340
!
!     Pick the next search direction of stage two.
!
320     temp = 1.0_wp / zdota (nact)
        do 330 i = 1, n
330     sdirn (i) = temp * z (i, nact)
!
!     Calculate the step to the boundary of the trust region or take the step
!     that reduces RESMAX to zero. The two statements below that include the
!     factor 1.0E-6 prevent some harmless underflows that occurred in a test
!     calculation. Further, we skip the step if it could be zero within a
!     reasonable tolerance for computer rounding errors.
!
340     dd = rho * rho
        sd = 0.0_wp
        ss = 0.0_wp
        do 350 i = 1, n
            if (abs(dx(i)) >= 1.0e-6_wp*rho) dd = dd - dx (i) ** 2
            sd = sd + dx (i) * sdirn (i)
350     ss = ss + sdirn (i) ** 2
        if (dd <= 0.0_wp) go to 490
        temp = sqrt (ss*dd)
        if (abs(sd) >= 1.0e-6_wp*temp) temp = sqrt (ss*dd+sd*sd)
        stpful = dd / (temp+sd)
        step = stpful
        if (mcon == m) then
            acca = step + 0.1_wp * resmax
            accb = step + 0.2_wp * resmax
            if (step >= acca .or. acca >= accb) go to 480
            step = min (step, resmax)
        end if
!
!     Set DXNEW to the new variables if STEP is the steplength, and reduce
!     RESMAX to the corresponding maximum residual if stage one is being done.
!     Because DXNEW will be changed during the calculation of some Lagrange
!     multipliers, it will be restored to the following value later.
!
        do 360 i = 1, n
360     dxnew (i) = dx (i) + step * sdirn (i)
        if (mcon == m) then
            resold = resmax
            resmax = 0.0_wp
            do 380 k = 1, nact
                kk = iact (k)
                temp = b (kk)
                do 370 i = 1, n
370             temp = temp - a (i, kk) * dxnew (i)
                resmax = max (resmax, temp)
380         continue
        end if
!
!     Set VMULTD to the VMULTC vector that would occur if DX became DXNEW. A
!     device is included to force VMULTD(K)=0.0 if deviations from this value
!     can be attributed to computer rounding errors. First calculate the new
!     Lagrange multipliers.
!
        k = nact
390     zdotw = 0.0_wp
        zdwabs = 0.0_wp
        do 400 i = 1, n
            temp = z (i, k) * dxnew (i)
            zdotw = zdotw + temp
400     zdwabs = zdwabs + abs (temp)
        acca = zdwabs + 0.1_wp * abs (zdotw)
        accb = zdwabs + 0.2_wp * abs (zdotw)
        if (zdwabs >= acca .or. acca >= accb) zdotw = 0.0_wp
        vmultd (k) = zdotw / zdota (k)
        if (k >= 2) then
            kk = iact (k)
            do 410 i = 1, n
410         dxnew (i) = dxnew (i) - vmultd (k) * a (i, kk)
            k = k - 1
            go to 390
        end if
        if (mcon > m) vmultd (nact) = max (0.0_wp, vmultd(nact))
!
!     Complete VMULTC by finding the new constraint residuals.
!
        do 420 i = 1, n
420     dxnew (i) = dx (i) + step * sdirn (i)
        if (mcon > nact) then
            kl = nact + 1
            do 440 k = kl, mcon
                kk = iact (k)
                sum = resmax - b (kk)
                sumabs = resmax + abs (b(kk))
                do 430 i = 1, n
                    temp = a (i, kk) * dxnew (i)
                    sum = sum + temp
430             sumabs = sumabs + abs (temp)
                acca = sumabs + 0.1_wp * abs (sum)
                accb = sumabs + 0.2_wp * abs (sum)
                if (sumabs >= acca .or. acca >= accb) sum = 0.0_wp
440         vmultd (k) = sum
        end if
!
!     Calculate the fraction of the step from DX to DXNEW that will be taken.
!
        ratio = 1.0_wp
        icon = 0
        do 450 k = 1, mcon
            if (vmultd(k) < 0.0_wp) then
                temp = vmultc (k) / (vmultc(k)-vmultd(k))
                if (temp < ratio) then
                    ratio = temp
                    icon = k
                end if
            end if
450     continue
!
!     Update DX, VMULTC and RESMAX.
!
        temp = 1.0_wp - ratio
        do 460 i = 1, n
460     dx (i) = temp * dx (i) + ratio * dxnew (i)
        do 470 k = 1, mcon
470     vmultc (k) = max (0.0_wp, temp*vmultc(k)+ratio*vmultd(k))
        if (mcon == m) resmax = resold + ratio * (resmax-resold)
!
!     If the full step is not acceptable then begin another iteration.
!     Otherwise switch to stage two or end the calculation.
!
        if (icon > 0) go to 70
        if (step == stpful) go to 500
480     mcon = m + 1
        icon = mcon
        iact (mcon) = mcon
        vmultc (mcon) = 0.0_wp
        go to 60
!
!     We employ any freedom that may be available to reduce the objective
!     function before returning a DX whose length is less than RHO.
!
490     if (mcon == m) go to 480
        ifull = 0
500     return
    end subroutine trstlp
 
    subroutine cobyla_test ()
!------------------------------------------------------------------------------
!     Main program of test problems in Report DAMTP 1992/NA5.
!------------------------------------------------------------------------------
    !Common nprob
        dimension x (10), xopt (10), w (3000), iact (51)
        do 180 nprob = 1, 10
            if (nprob == 1) then
    !
    !     minimization of a simple quadratic function of two variables.
    !
                print 10
10              format (/ 7 x, 'Output from test problem 1 (Simple quadratic)')
                n = 2
                m = 0
                xopt (1) = - 1.0_wp
                xopt (2) = 0.0_wp
            else if (nprob == 2) then
    !
    !     Easy two dimensional minimization in unit circle.
    !
                print 20
20              format (/ 7 x, 'Output from test problem 2 (2D unit circle ',&
                'calculation)')
                n = 2
                m = 1
                xopt (1) = sqrt (0.5_wp)
                xopt (2) = - xopt (1)
            else if (nprob == 3) then
    !
    !     Easy three dimensional minimization in ellipsoid.
    !
                print 30
30              format (/ 7 x, 'Output from test problem 3 (3D ellipsoid ',&
                'calculation)')
                n = 3
                m = 1
                xopt (1) = 1.0_wp / sqrt (3.0_wp)
                xopt (2) = 1.0_wp / sqrt (6.0_wp)
                xopt (3) = - 1.0_wp / 3.0_wp
            else if (nprob == 4) then
    !
    !     Weak version of Rosenbrock's problem.
    !
                print 40
40              format (/ 7 x, 'Output from test problem 4 (Weak Rosenbrock)')
                n = 2
                m = 0
                xopt (1) = - 1.0_wp
                xopt (2) = 1.0_wp
            else if (nprob == 5) then
    !
    !     Intermediate version of Rosenbrock's problem.
    !
                print 50
50              format (/ 7 x, 'Output from test problem 5 (Intermediate ', 'Rosenbrock)')
                n = 2
                m = 0
                xopt (1) = - 1.0_wp
                xopt (2) = 1.0_wp
            else if (nprob == 6) then
    !
    !     This problem is taken from Fletcher's book Practical Methods of
    !     Optimization and has the equation number (9.1.15).
    !
                print 60
60              format (/ 7 x, 'Output from test problem 6 (Equation ',&
                '(9.1.15) in Fletcher)')
                n = 2
                m = 2
                xopt (1) = sqrt (0.5_wp)
                xopt (2) = xopt (1)
            else if (nprob == 7) then
    !
    !     This problem is taken from Fletcher's book Practical Methods of
    !     Optimization and has the equation number (14.4.2).
    !
                print 70
70              format (/ 7 x, 'Output from test problem 7 (Equation ',&
                '(14.4.2) in Fletcher)')
                n = 3
                m = 3
                xopt (1) = 0.0_wp
                xopt (2) = - 3.0_wp
                xopt (3) = - 3.0_wp
            else if (nprob == 8) then
    !
    !     This problem is taken from page 66 of Hock and Schittkowski's book Test
    !     Examples for Nonlinear Programming Codes. It is their test problem Number
    !     43, and has the name Rosen-Suzuki.
    !
                print 80
80              format (/ 7 x, 'Output from test problem 8 (Rosen-Suzuki)')
                n = 4
                m = 3
                xopt (1) = 0.0_wp
                xopt (2) = 1.0_wp
                xopt (3) = 2.0_wp
                xopt (4) = - 1.0_wp
            else if (nprob == 9) then
    !
    !     This problem is taken from page 111 of Hock and Schittkowski's
    !     book Test Examples for Nonlinear Programming Codes. It is their
    !     test problem Number 100.
    !
                print 90
90              format (/ 7 x, 'Output from test problem 9 (Hock and ',&
                'Schittkowski 100)')
                n = 7
                m = 4
                xopt (1) = 2.330499_wp
                xopt (2) = 1.951372_wp
                xopt (3) = - 0.4775414_wp
                xopt (4) = 4.365726_wp
                xopt (5) = - 0.624487_wp
                xopt (6) = 1.038131_wp
                xopt (7) = 1.594227_wp
            else if (nprob == 10) then
    !
    !     This problem is taken from page 415 of Luenberger's book Applied
    !     Nonlinear Programming. It is to maximize the area of a hexagon of
    !     unit diameter.
    !
                print 100
100             format (/ 7 x, 'Output from test problem 10 (Hexagon area)')
                n = 9
                m = 14
            end if
            do 160 icase = 1, 2
                do 120 i = 1, n
120             x (i) = 1.0_wp
                rhobeg = 0.5_wp
                rhoend = 0.001_wp
                if (icase == 2) rhoend = 0.0001_wp
                iprint = 1
                maxfun = 2000
                call cobyla (n, m, x, rhobeg, rhoend, iprint, maxfun, w, iact, calcfc)
                if (nprob == 10) then
                    tempa = x (1) + x (3) + x (5) + x (7)
                    tempb = x (2) + x (4) + x (6) + x (8)
                    tempc = 0.5_wp / sqrt (tempa*tempa+tempb*tempb)
                    tempd = tempc * sqrt (3.0_wp)
                    xopt (1) = tempd * tempa + tempc * tempb
                    xopt (2) = tempd * tempb - tempc * tempa
                    xopt (3) = tempd * tempa - tempc * tempb
                    xopt (4) = tempd * tempb + tempc * tempa
                    do 130 i = 1, 4
130                 xopt (i+4) = xopt (i)
                end if
                temp = 0.0_wp
                do 140 i = 1, n
140             temp = temp + (x(i)-xopt(i)) ** 2
                print 150, sqrt (temp)
150             format (/ 5 x, 'Least squares error in variables =', 1 pe16.6)
160         continue
            print 170
170         format (2 x, '----------------------------------------------',&
            '--------------------')
180     continue
 
    contains
 
        subroutine calcfc (n, m, x, f, con)
          !Common nprob
            dimension x (*), con (*)
            if (nprob == 1) then
    !
    !     Test problem 1 (Simple quadratic)
    !
                f = 10.0_wp * (x(1)+1.0_wp) ** 2 + x (2) ** 2
            else if (nprob == 2) then
    !
    !    Test problem 2 (2D unit circle calculation)
    !
                f = x (1) * x (2)
                con (1) = 1.0_wp - x (1) ** 2 - x (2) ** 2
            else if (nprob == 3) then
    !
    !     Test problem 3 (3D ellipsoid calculation)
    !
                f = x (1) * x (2) * x (3)
                con (1) = 1.0_wp - x (1) ** 2 - 2.0_wp * x (2) ** 2 - 3.0_wp * x (3) ** 2
            else if (nprob == 4) then
    !
    !     Test problem 4 (Weak Rosenbrock)
    !
                f = (x(1)**2-x(2)) ** 2 + (1.0_wp+x(1)) ** 2
            else if (nprob == 5) then
    !
    !     Test problem 5 (Intermediate Rosenbrock)
    !
                f = 10.0_wp * (x(1)**2-x(2)) ** 2 + (1.0_wp+x(1)) ** 2
            else if (nprob == 6) then
    !
    !     Test problem 6 (Equation (9.1.15) in Fletcher's book)
    !
                f = - x (1) - x (2)
                con (1) = x (2) - x (1) ** 2
                con (2) = 1.0_wp - x (1) ** 2 - x (2) ** 2
            else if (nprob == 7) then
    !
    !     Test problem 7 (Equation (14.4.2) in Fletcher's book)
    !
                f = x (3)
                con (1) = 5.0_wp * x (1) - x (2) + x (3)
                con (2) = x (3) - x (1) ** 2 - x (2) ** 2 - 4.0_wp * x (2)
                con (3) = x (3) - 5.0_wp * x (1) - x (2)
            else if (nprob == 8) then
    !
    !     Test problem 8 (Rosen-Suzuki)
    !
                f = x (1) ** 2 + x (2) ** 2 + 2.0_wp * x (3) ** 2 + x (4) ** 2 - 5.0_wp * &
               & x (1) - 5.0_wp * x (2) - 21.0_wp * x (3) + 7.0_wp * x (4)
                con (1) = 8.0_wp - x (1) ** 2 - x (2) ** 2 - x (3) ** 2 - x (4) ** 2 - x &
               & (1) + x (2) - x (3) + x (4)
                con (2) = 10.0_wp - x (1) ** 2 - 2.0_wp * x (2) ** 2 - x (3) ** 2 - &
               & 2.0_wp * x (4) ** 2 + x (1) + x (4)
                con (3) = 5.0_wp - 2.0_wp * x (1) ** 2 - x (2) ** 2 - x (3) ** 2 - 2.0_wp &
               & * x (1) + x (2) + x (4)
            else if (nprob == 9) then
    !
    !     Test problem 9 (Hock and Schittkowski 100)
    !
                f = (x(1)-10.0_wp) ** 2 + 5.0_wp * (x(2)-12.0_wp) ** 2 + x (3) ** 4 + &
               & 3.0_wp * (x(4)-11.0_wp) ** 2 + 10.0_wp * x (5) ** 6 + 7.0_wp * x (6) ** &
               & 2 + x (7) ** 4 - 4.0_wp * x (6) * x (7) - 10.0_wp * x (6) - 8.0_wp * x &
               & (7)
                con (1) = 127.0_wp - 2.0_wp * x (1) ** 2 - 3.0_wp * x (2) ** 4 - x (3) - &
               & 4.0_wp * x (4) ** 2 - 5.0_wp * x (5)
                con (2) = 282.0_wp - 7.0_wp * x (1) - 3.0_wp * x (2) - 10.0_wp * x (3) ** &
               & 2 - x (4) + x (5)
                con (3) = 196.0_wp - 23.0_wp * x (1) - x (2) ** 2 - 6.0_wp * x (6) ** 2 + &
               & 8.0_wp * x (7)
                con (4) = - 4.0_wp * x (1) ** 2 - x (2) ** 2 + 3.0_wp * x (1) * x (2) - &
               & 2.0_wp * x (3) ** 2 - 5.0_wp * x (6) + 11.0_wp * x (7)
            else if (nprob == 10) then
    !
    !     Test problem 10 (Hexagon area)
    !
                f = - 0.5_wp * &
               & (x(1)*x(4)-x(2)*x(3)+x(3)*x(9)-x(5)*x(9)+x(5)*x(8)-x(6)*x(7))
                con (1) = 1.0_wp - x (3) ** 2 - x (4) ** 2
                con (2) = 1.0_wp - x (9) ** 2
                con (3) = 1.0_wp - x (5) ** 2 - x (6) ** 2
                con (4) = 1.0_wp - x (1) ** 2 - (x(2)-x(9)) ** 2
                con (5) = 1.0_wp - (x(1)-x(5)) ** 2 - (x(2)-x(6)) ** 2
                con (6) = 1.0_wp - (x(1)-x(7)) ** 2 - (x(2)-x(8)) ** 2
                con (7) = 1.0_wp - (x(3)-x(5)) ** 2 - (x(4)-x(6)) ** 2
                con (8) = 1.0_wp - (x(3)-x(7)) ** 2 - (x(4)-x(8)) ** 2
                con (9) = 1.0_wp - x (7) ** 2 - (x(8)-x(9)) ** 2
                con (10) = x (1) * x (4) - x (2) * x (3)
                con (11) = x (3) * x (9)
                con (12) = - x (5) * x (9)
                con (13) = x (5) * x (8) - x (6) * x (7)
                con (14) = x (9)
            end if
        end subroutine calcfc
 
    end subroutine cobyla_test
 
end module cobyla_module
