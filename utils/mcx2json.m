function mcx2json(cfg, filestub)
%
% Format:
%    mcx2json(cfg,filestub)
%
% Save MCXLAB simulation configuration to a JSON file for MCX binary
%
% Author: Qianqian Fang <q.fang at neu.edu>
%
% Input:
%    cfg: a struct defining the parameters associated with a simulation.
%         Please run 'help mcxlab' or 'help mmclab' to see the details.
%         mcxpreview supports the cfg input for both mcxlab and mmclab.
%    filestub: the filestub is the name stub for all output files,including
%         filestub.json: the JSON input file
%         filestub_vol.bin: the volume file if cfg.vol is defined
%         filestub_shapes.json: the domain shape file if cfg.shapes is defined
%         filestub_pattern.bin: the domain shape file if cfg.pattern is defined
%
% Dependency:
%    this function depends on the savejson/saveubjson functions from the
%    Iso2Mesh toolbox (http://iso2mesh.sf.net) or JSONlab toolbox
%    (http://iso2mesh.sf.net/jsonlab)
%
% This function is part of Monte Carlo eXtreme (MCX) URL: http://mcx.space
%
% License: GNU General Public License version 3, please read LICENSE.txt for details
%

[fpath, fname, fext] = fileparts(filestub);
filestub = fullfile(fpath, fname);

%% define the optodes: sources and detectors

Optode.Source = struct();
Optode.Source = copycfg(cfg, 'srcpos', Optode.Source, 'Pos');
Optode.Source = copycfg(cfg, 'srcdir', Optode.Source, 'Dir');
Optode.Source = copycfg(cfg, 'srciquv', Optode.Source, 'IQUV');
Optode.Source = copycfg(cfg, 'srcparam1', Optode.Source, 'Param1');
Optode.Source = copycfg(cfg, 'srcparam2', Optode.Source, 'Param2');
Optode.Source = copycfg(cfg, 'srctype', Optode.Source, 'Type');
Optode.Source = copycfg(cfg, 'srcnum', Optode.Source, 'SrcNum');
Optode.Source = copycfg(cfg, 'lambda', Optode.Source, 'WaveLength');

if (isfield(cfg, 'detpos') && ~isempty(cfg.detpos))
    Optode.Detector = struct();
    Optode.Detector = cell2struct(mat2cell(cfg.detpos, ones(1, size(cfg.detpos, 1)), [3 1]), {'Pos', 'R'}, 2);
    Optode.Detector = Optode.Detector(:)';
    if (length(Optode.Detector) == 1)
        Optode.Detector = {Optode.Detector};
    end
end
if (isfield(cfg, 'srcpattern') && ~isempty(cfg.srcpattern))
    Optode.Source.Pattern = single(cfg.srcpattern);
end

%% define the domain and optical properties

Domain = struct();
Domain = copycfg(cfg, 'issrcfrom0', Domain, 'OriginType', 0);
Domain = copycfg(cfg, 'unitinmm', Domain, 'LengthUnit');
Domain = copycfg(cfg, 'invcdf', Domain, 'InverseCDF');
Domain = copycfg(cfg, 'angleinvcdf', Domain, 'AngleInverseCDF');

Domain.Media = cell2struct(num2cell(cfg.prop), {'mua', 'mus', 'g', 'n'}, 2)';

if (isfield(cfg, 'polprop') && ~isempty(cfg.polprop))
    Domain.MieScatter = cell2struct(num2cell(cfg.polprop), {'mua', 'radius', 'rho', 'nsph', 'nmed'}, 2)';
end

if (isfield(cfg, 'shapes') && ischar(cfg.shapes))
    Shapes = loadjson(cfg.shapes);
    Shapes = Shapes.Shapes;
end

if (isfield(cfg, 'vol') && ~isempty(cfg.vol) && ~isfield(Domain, 'VolumeFile'))
    switch (class(cfg.vol))
        case {'uint8', 'int8'}
            Domain.MediaFormat = 'byte';
            if (ndims(cfg.vol) == 4 && size(cfg.vol, 1) == 4)
                Domain.MediaFormat = 'asgn_byte';
            elseif (ndims(cfg.vol) == 4 && size(cfg.vol, 1) == 8)
                cfg.vol = reshape(typecast(uint8(cfg.vol(:)), 'uint64'), size(cfg.vol, 2, 3, 4));
                Domain.MediaFormat = 'svmc';
            end
        case {'uint16', 'int16'}
            Domain.MediaFormat = 'short';
            if (ndims(cfg.vol) == 4 && size(cfg.vol, 1) == 2)
                Domain.MediaFormat = 'muamus_short';
            end
        case {'uint32', 'int32'}
            Domain.MediaFormat = 'integer';
        case {'single', 'double'}
            if (isa(cfg.vol, 'double'))
                cfg.vol = single(cfg.vol);
            end
            if (all(mod(cfg.vol(:), 1) == 0))
                if (max(cfg.vol(:)) < 256)
                    Domain.MediaFormat = 'byte';
                    cfg.vol = uint8(cfg.vol);
                else
                    Domain.MediaFormat = 'integer';
                    cfg.vol = uint32(cfg.vol);
                end
            elseif (ndims(cfg.vol) == 4)
                if (size(cfg.vol, 1)) == 1
                    Domain.MediaFormat = 'mua_float';
                elseif (size(cfg.vol, 1) == 2)
                    Domain.MediaFormat = 'muamus_float';
                elseif (size(cfg.vol, 1) == 4)
                    Domain.MediaFormat = 'asgn_float';
                end
            end
        otherwise
            error('cfg.vol has format that is not supported');
    end

    Domain.Dim = size(cfg.vol);
    if (length(Domain.Dim) == 4)
        Domain.Dim(1) = [];
    end
    if (exist('Shapes', 'var'))
        if (isempty(regexp(savejson('', Shapes, 'compact', 1), '"Grid"', 'once')))
            Domain.VolumeFile = [filestub '_vol.bin'];
            fid = fopen(Domain.VolumeFile, 'wb');
            fwrite(fid, cfg.vol, class(cfg.vol));
            fclose(fid);
        end
    else
        Domain.VolumeFile = '';
        Shapes = cfg.vol;
        if (ndims(Shapes) == 4 && size(Shapes, 1) > 1)
            Shapes = permute(Shapes, [2 3 4 1]);
        end
    end
end

%% define the simulation session flags

Session.ID = filestub;
Session = copycfg(cfg, 'isreflect', Session, 'DoMismatch');
Session = copycfg(cfg, 'issave2pt', Session, 'DoSaveVolume');
Session = copycfg(cfg, 'issavedet', Session, 'DoPartialPath');
Session = copycfg(cfg, 'issaveexit', Session, 'DoSaveExit');
Session = copycfg(cfg, 'issaveseed', Session, 'DoSaveSeed');
Session = copycfg(cfg, 'isnormalize', Session, 'DoNormalize');
Session = copycfg(cfg, 'outputformat', Session, 'OutputFormat');
Session = copycfg(cfg, 'outputtype', Session, 'OutputType');
Session = copycfg(cfg, 'debuglevel', Session, 'Debug');
Session = copycfg(cfg, 'autopilot', Session, 'DoAutoThread');
Session = copycfg(cfg, 'maxdetphoton', Session, 'MaxDetPhoton');
Session = copycfg(cfg, 'bc', Session, 'BCFlags');

if (isfield(cfg, 'savedetflag') && ~isempty(cfg.savedetflag) && ischar(cfg.savedetflag))
    cfg.savedetflag = upper(cfg.savedetflag);
end
Session = copycfg(cfg, 'savedetflag', Session, 'SaveDataMask');

if (isfield(cfg, 'seed') && numel(cfg.seed) == 1)
    Session.RNGSeed = cfg.seed;
end
Session = copycfg(cfg, 'nphoton', Session, 'Photons');
Session = copycfg(cfg, 'minenergy', Session, 'MinEnergy');
Session = copycfg(cfg, 'rootpath', Session, 'RootPath');

%% define the forward simulation settings

Forward.T0 = cfg.tstart;
Forward.T1 = cfg.tend;
Forward.Dt = cfg.tstep;

%% assemble the complete input, save to a JSON or UBJSON input file

mcxsession = struct('Session', Session, 'Forward', Forward, 'Optode', Optode, 'Domain', Domain);
if (exist('Shapes', 'var'))
    mcxsession.Shapes = Shapes;
end
if (strcmp(fext, 'ubj'))
    saveubjson('', mcxsession, [filestub, '.ubj']);
else
    savejson('', mcxsession, 'filename', [filestub, '.json'], 'compression', 'zlib');
end

function outdata = copycfg(cfg, name, outroot, outfield, defaultval)
if (nargin >= 5)
    outroot.(outfield) = defaultval;
end
if (isfield(cfg, name))
    outroot.(outfield) = cfg.(name);
end
outdata = outroot;
