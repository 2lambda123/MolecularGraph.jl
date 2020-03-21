
@testset "smarts.stereo" begin

@testset "addchiralhydrogens" begin
    LAla = parse(SMILES, "N[C@H](C)C(=O)O")
    @test nodecount(LAla) == 6
    LAla_ = addchiralhydrogens(LAla)
    @test nodecount(LAla_) == 7
    @test LAla_.nodeattrs[2].stereo == :anticlockwise
    @test LAla_.nodeattrs[3].symbol == :H
end

@testset "removechiralhydrogens" begin
    LAla1 = parse(SMILES, "N[C@@]([H])(C)C(=O)O")
    @test LAla1.nodeattrs[2].stereo == :clockwise
    LAla1_ = removechiralhydrogens(LAla1)
    @test nodecount(LAla1_) == 6
    @test LAla1_.nodeattrs[2].stereo == :clockwise
    @test LAla1_.nodeattrs[3].symbol == :C
    
    LAla2 = parse(SMILES, "N[C@@](C)([H])C(=O)O")
    LAla2_ = removechiralhydrogens(LAla2)
    @test nodecount(LAla2_) == 6
    @test LAla2_.nodeattrs[2].stereo == :anticlockwise
    
    LAla3 = parse(SMILES, "[H][C@@](C)(N)C(=O)O")
    LAla3_ = removechiralhydrogens(LAla3)
    @test nodecount(LAla3_) == 6
    @test LAla3_.nodeattrs[1].stereo == :clockwise

    LAla4 = parse(SMILES, "N[C@@](C)(C(=O)O)[H]")
    LAla4_ = removechiralhydrogens(LAla4)
    @test nodecount(LAla4_) == 6
    @test LAla4_.nodeattrs[2].stereo == :clockwise
end

@testset "chiralcenter" begin
    LAla = parse(SMILES, "N[C@H](C)C(=O)O")
    chiralcenter_ = chiralcenter(LAla)
    @test chiralcenter_[2] == (1, -1, 4, 3)

    LAla2 = parse(SMILES, "N[C@@](C)([H])C(=O)O")
    chiralcenter2_ = chiralcenter(LAla2)
    @test chiralcenter2_[2] == (1, 3, 4, 5)
    LAla2_ = removechiralhydrogens(LAla2)
    chiralcenter2__ = chiralcenter(LAla2_)
    @test chiralcenter2__[2] == (1, -1, 4, 3)

    LAla3 = parse(SMILES, "[H][C@@](C)(N)C(=O)O")
    chiralcenter3_ = chiralcenter(LAla3)
    @test chiralcenter3_[2] == (1, 3, 4, 5)

    LAla4 = parse(SMILES, "N[C@@](C)(C(=O)O)[H]")
    chiralcenter4_ = chiralcenter(LAla4)
    @test chiralcenter4_[2] == (1, 3, 4, 7)
end

@testset "diastereobond" begin
    cis = parse(SMILES, "C\\C([H])=C([H])/C")
    diastereo_ = diastereobond(cis)
    @test diastereo_[3] == (1, 5, :cis)

    trans = parse(SMILES, "C\\C([H])=C([H])\\C")
    diastereo2_ = diastereobond(trans)
    @test diastereo2_[3] == (1, 5, :trans)

    trans2 = parse(SMILES, "C/C([H])=C([H])/C")
    diastereo3_ = diastereobond(trans2)
    @test diastereo3_[3] == (1, 5, :trans)
end

end # smarts.stereo
